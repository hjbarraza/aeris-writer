import AppKit
import LibraryCore

/// The app-wide library: the folders added to the sidebar and the lazy tree below them.
/// Every window's sidebar shares it and is told when the roots change.
@MainActor
final class Library {
    static let shared = Library(store: LocationStore(fileURL: LocationStore.defaultFileURL))

    let tree = LibraryTree()
    private let store: LocationStore
    private let sidebars = NSHashTable<SidebarViewController>.weakObjects()
    private let fileLists = NSHashTable<FileListViewController>.weakObjects()
    /// Watches every root; rebuilt whenever the roots change.
    private var watcher: FolderWatcher?

    /// Shows an error to the user (an alert); replaced in self-checks.
    var reportError: (_ message: String, _ detail: String) -> Void = { message, detail in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    init(store: LocationStore) {
        self.store = store
        store.load()
        reload()
        if store.loadFailed {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.reportError("The list of library locations could not be read.",
                                      "The file was left as it is and copied to a .backup file next to it before any change replaces it.")
                }
            }
        }
    }

#if DEBUG
    var watcherForTesting: AnyObject? { watcher }
#endif

    func register(_ sidebar: SidebarViewController) {
        sidebars.add(sidebar)
    }

    func register(_ list: FileListViewController) {
        fileLists.add(list)
    }

    /// Appends `url` unless a location with the same canonical path already exists.
    func addLocation(_ url: URL) {
        do {
            guard try store.add(url) else { return }
        } catch {
            NSLog("Aeris: could not save location %@: %@", url.path, "\(error)")
            reportError("The location could not be added.", "Saving the list of locations failed: \(error.localizedDescription) The list is unchanged.")
            return
        }
        reload()
    }

    /// Removes the location at `index` (a root row) from the library; the folder on disk is untouched.
    func removeLocation(at index: Int) {
        do {
            try store.remove(at: index)
        } catch {
            NSLog("Aeris: could not remove location %d: %@", index, "\(error)")
            reportError("The location could not be removed.", "Saving the list of locations failed: \(error.localizedDescription) The list is unchanged.")
            return
        }
        reload()
    }

    /// The user's display name for the location at `index`, nil if none is set.
    func label(at index: Int) -> String? {
        store.locations.indices.contains(index) ? store.locations[index].label : nil
    }

    /// Sets (or, when blank, clears) the display name of the location at `index`; the folder is untouched.
    func setLabel(_ label: String?, at index: Int) {
        do {
            try store.setLabel(label, at: index)
        } catch {
            NSLog("Aeris: could not save location label %d: %@", index, "\(error)")
            reportError("The name could not be saved.", "Saving the list of locations failed: \(error.localizedDescription) The list is unchanged.")
            return
        }
        for sidebar in sidebars.allObjects { sidebar.libraryRootsDidChange() }
    }

    /// Re-resolves every bookmark (an unresolvable one keeps its stored path) and updates the roots.
    func reload() {
        let urls = store.locations.indices.map { store.resolve(at: $0) ?? URL(fileURLWithPath: store.locations[$0].path) }
        tree.setRoots(urls)
        // The new stream starts before the re-list and the old one stops after it, so no event
        // falls in between (a root may have been recreated); the sidebars reload from the tree below.
        let old = watcher
        watcher = FolderWatcher(paths: tree.roots.map(\.path)) { [weak self] in self?.folderChanged($0) }
        _ = tree.refresh(tree.roots.map { FolderChange(path: $0.path, mustScanSubDirs: true, rootChanged: false) })
        old?.stop()
        for sidebar in sidebars.allObjects { sidebar.libraryRootsDidChange() }
        for list in fileLists.allObjects { list.libraryRootsDidChange() }
    }

    /// A file's content changed (disk event or a save): every list re-checks the dates and excerpts it shows.
    func refreshRows() {
        for list in fileLists.allObjects { list.refreshVisibleRows() }
    }

    /// Disk changes: a moved or deleted root re-resolves every bookmark and re-lists every loaded
    /// folder (so no other change in the batch is lost); anything else re-lists only the loaded
    /// folders involved and tells each file list what changed.
    func folderChanged(_ changes: [FolderChange]) {
        if changes.contains(where: \.rootChanged) {
            // Not inside the stream's callback: reload stops the stream that is still delivering.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.reload() }
            }
            return
        }
        let treeChanges = tree.refresh(changes)
        refreshRows()
        guard !treeChanges.isEmpty else { return }
        for list in fileLists.allObjects { list.apply(treeChanges) }
    }
}
