import Foundation

/// One library folder: a bookmark that follows the folder when it is renamed or moved,
/// plus the last known path (shown when the bookmark no longer resolves).
public struct Location: Codable, Equatable, Sendable {
    public var bookmark: Data
    public var path: String
    /// Display name set by the user; nil shows the folder's own name. The folder on disk is never renamed.
    public var label: String?
}

/// The persisted list of library locations (binary plist, no sandbox, plain bookmarks).
public final class LocationStore {
    private struct File: Codable {
        var version = 1
        var locations: [Location]
    }

    private let fileURL: URL
    public private(set) var locations: [Location] = []
    /// Set when the file exists but could not be read; the list is then empty and the file's
    /// bytes are copied to `<file>.backup` before the first save replaces them.
    public private(set) var loadFailed = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `$AERIS_LIBRARY_FILE`, else `~/Library/Application Support/Aeris/Locations.plist`.
    public static var defaultFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["AERIS_LIBRARY_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Aeris/Locations.plist")
    }

    /// Reads the file; a missing or unreadable file leaves the store empty (`loadFailed` tells them apart).
    public func load() {
        loadFailed = false
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? PropertyListDecoder().decode(File.self, from: data) else {
            locations = []
            loadFailed = FileManager.default.fileExists(atPath: fileURL.path)
            return
        }
        locations = file.locations
    }

    /// Adds `folder` unless a location with the same canonical path exists. Returns whether it was added.
    @discardableResult
    public func add(_ folder: URL) throws -> Bool {
        let path = LibraryListing.canonicalPath(folder)
        if locations.indices.contains(where: { LibraryListing.canonicalPath(resolvedURL(at: $0) ?? URL(fileURLWithPath: locations[$0].path)) == path }) {
            return false
        }
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try commit(locations + [Location(bookmark: bookmark, path: path)])
        return true
    }

    public func remove(at index: Int) throws {
        guard locations.indices.contains(index) else { return }
        var updated = locations
        updated.remove(at: index)
        try commit(updated)
    }

    /// Sets the display name of the location at `index`. Blank (after trimming) clears it.
    public func setLabel(_ label: String?, at index: Int) throws {
        guard locations.indices.contains(index) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = locations
        updated[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try commit(updated)
    }

    /// Resolves the bookmark. A moved or renamed folder updates the stored path (and a stale
    /// bookmark is re-created and saved). Nil if the folder no longer exists.
    public func resolve(at index: Int) -> URL? {
        guard locations.indices.contains(index), let (url, stale) = resolveBookmark(at: index) else { return nil }
        let path = LibraryListing.canonicalPath(url)
        var changed = false
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            locations[index].bookmark = fresh
            changed = true
        }
        if locations[index].path != path {
            locations[index].path = path
            changed = true
        }
        if changed { try? save() }
        return url
    }

    private func resolveBookmark(at index: Int) -> (URL, Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: locations[index].bookmark,
                                 options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path),
              !url.pathComponents.contains(".Trash") else { return nil }  // trashed counts as missing
        return (url, stale)
    }

    /// Resolution without side effects, for duplicate detection.
    private func resolvedURL(at index: Int) -> URL? {
        resolveBookmark(at: index)?.0
    }

    /// Saves `updated`; the in-memory list changes only when the save succeeded.
    private func commit(_ updated: [Location]) throws {
        let previous = locations
        locations = updated
        do { try save() } catch {
            locations = previous
            throw error
        }
    }

    private func save() throws {
        if loadFailed {
            // Keep the unreadable file's bytes; never silently replace them with a shorter list.
            let backup = fileURL.appendingPathExtension("backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: fileURL, to: backup)
            loadFailed = false
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(File(locations: locations)).write(to: fileURL, options: .atomic)
    }
}
