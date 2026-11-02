import AppKit

/// The file list's file operations: create, duplicate, rename, move and trash. The app never deletes
/// permanently: Move to Trash is the only way an item leaves (H, 2026-10-29). Each runs
/// off the main thread through `FileManager` under file coordination, so an open document (a file
/// presenter) follows a rename or a move. Nothing ever overwrites an existing item: `moveItem`,
/// `copyItem`, `createDirectory` and a `.withoutOverwriting` write all fail if the name is taken.
enum FileOperations {
    struct Failure: Sendable {
        let url: URL
        let error: Error
    }

    /// The items an operation made or moved to, and what went wrong.
    struct Outcome: Sendable {
        var made: [URL] = []
        var failures: [Failure] = []
    }

    /// Moves an item to the Trash and returns where it went. A seam so the self-check never
    /// touches the real Trash.
    nonisolated(unsafe) static var trashItem: (URL) throws -> URL? = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    /// Shows what failed, in one alert (a sheet on `window`). A seam so a headless check shows nothing.
    @MainActor static var presentFailures: (_ title: String, _ failures: [Failure], _ window: NSWindow?) -> Void = { title, failures, window in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = failures.map { "“\($0.url.lastPathComponent)”: \($0.error.localizedDescription)" }
            .joined(separator: "\n")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Warns before a rename that would take the item out of the list; `answer` gets the index of the
    /// button chosen (0 is the default). A seam so a headless check shows nothing.
    @MainActor static var askRename: (_ message: String, _ buttons: [String], _ window: NSWindow?, _ answer: @escaping @MainActor (Int) -> Void) -> Void = { message, buttons, window, answer in
        let alert = NSAlert()
        alert.messageText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        let index = { (response: NSApplication.ModalResponse) in response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue }
        if let window {
            alert.beginSheetModal(for: window) { answer(index($0)) }
        } else {
            answer(index(alert.runModal()))
        }
    }

    private static let queue = DispatchQueue(label: "aeris.fileoperations", qos: .userInitiated)

    /// Runs `work` off the main thread; `done` gets its outcome on the main thread.
    @MainActor static func run(_ work: @escaping @Sendable () -> Outcome, done: @escaping @MainActor (Outcome) -> Void) {
        queue.async {
            let outcome = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { done(outcome) } }
        }
    }

    /// Runs `step` on each URL, collecting what it made and every failure.
    static func each(_ urls: [URL], _ step: (URL) throws -> URL?) -> Outcome {
        var outcome = Outcome()
        for url in urls {
            do {
                if let made = try step(url) { outcome.made.append(made) }
            } catch {
                outcome.failures.append(Failure(url: url, error: error))
            }
        }
        return outcome
    }

    // MARK: Names

    /// `base` + `ext` in `folder`, or with " 2", " 3"… appended to `base` when the name is taken.
    static func freeURL(in folder: URL, base: String, ext: String) -> URL {
        func url(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return folder.appending(path: ext.isEmpty ? name : "\(name).\(ext)")
        }
        var n = 1
        while FileManager.default.fileExists(atPath: url(n).path) { n += 1 }
        return url(n)
    }

    // MARK: Coordinated steps

    /// Runs `step` inside `coordinate` (one of NSFileCoordinator's calls, given the error to fill
    /// and the body to run) and throws whichever failed.
    private static func coordinated(_ coordinate: (inout NSError?, () -> Void) -> Void, _ step: @escaping () throws -> Void) throws {
        var coordinationError: NSError?
        var stepError: Error?
        coordinate(&coordinationError) {
            do { try step() } catch { stepError = error }
        }
        if let error = coordinationError ?? stepError { throw error }
    }

    /// An empty file at `url`.
    static func createFile(at url: URL) throws {
        let c = NSFileCoordinator()
        try coordinated({ error, body in c.coordinate(writingItemAt: url, options: [], error: &error) { _ in body() } }) {
            try Data().write(to: url, options: .withoutOverwriting)
        }
    }

    /// A new folder at `url`.
    static func createFolder(at url: URL) throws {
        let c = NSFileCoordinator()
        try coordinated({ error, body in c.coordinate(writingItemAt: url, options: [], error: &error) { _ in body() } }) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
    }

    /// Moves (or renames) `source` to `destination`; an open document follows it.
    static func move(_ source: URL, to destination: URL) throws {
        let c = NSFileCoordinator()
        try coordinated({ error, body in c.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination,
                                       options: [], error: &error) { _, _ in body() } }) {
            c.item(at: source, willMoveTo: destination)
            try FileManager.default.moveItem(at: source, to: destination)
            c.item(at: source, didMoveTo: destination)
        }
    }

    /// Copies `source` to `destination`.
    static func copy(_ source: URL, to destination: URL) throws {
        let c = NSFileCoordinator()
        try coordinated({ error, body in c.coordinate(readingItemAt: source, options: [], writingItemAt: destination,
                                       options: [], error: &error) { _, _ in body() } }) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// Moves `url` to the Trash and returns where it went. A locked item is refused, as the
    /// Finder would ask first.
    static func trash(_ url: URL) throws -> URL? {
        if (try? url.resourceValues(forKeys: [.isUserImmutableKey]))?.isUserImmutable == true {
            throw CocoaError(.fileWriteNoPermission, userInfo: [
                NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” is locked.",
            ])
        }
        let c = NSFileCoordinator()
        var trashed: URL?
        try coordinated({ error, body in c.coordinate(writingItemAt: url, options: .forMoving, error: &error) { _ in body() } }) {
            trashed = try trashItem(url)
            if let trashed { c.item(at: url, didMoveTo: trashed) }
        }
        return trashed
    }
}
