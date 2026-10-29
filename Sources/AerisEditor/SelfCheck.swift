#if DEBUG
import AppKit
import WebKit
import MarkdownCore
import LibraryCore

/// Headless UI checks, run as `Aeris.app/Contents/MacOS/AerisEditor --selfcheck`.
/// Drives real controllers in never-ordered-in windows; never activates the app.
/// Prints `ok - …` / `FAIL - …`, ends with `selfcheck passed` (exit 0) or exits 1.
enum SelfCheck {
    nonisolated(unsafe) private static var failed = false

    /// Scratch folder for this run, holding the isolated library file and test folders.
    nonisolated(unsafe) private static var scratch = FileManager.default.temporaryDirectory
        .appending(path: "aeris-selfcheck-\(UUID().uuidString)")

    /// Points the library at a temp file. Called before anything touches `Library.shared`.
    static func isolateLibraryFile() {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        setenv("AERIS_LIBRARY_FILE", scratch.appending(path: "Locations.plist").path, 1)
    }

    @MainActor static func run() -> Never {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Aeris/Locations.plist").path
        guard LocationStore.defaultFileURL.path != real else {
            print("FAIL - isolation: default library file is H's real Locations.plist; refusing to run")
            exit(1)
        }
        check(true, "isolation: library file is a temp file, not the real Locations.plist")
        // Never show the convert alert: record the ask and answer Keep.
        MarkdownDocument.askToConvert = { _, example, answer in encodingAsks.append(example); answer(false) }
        // Never show the disk change sheet: record the ask and hold the answer.
        MarkdownDocument.askAboutDiskChange = { doc, change, answer in diskAsks.append((doc, change, answer)) }
        shellChecks()
        layoutChecks()
        libraryChecks()
        persistenceChecks()
        openChecks()
        sidebarChecks()
        organizerChecks()
        columnChecks()
        liveRefreshChecks()
        liveRefreshEdgeChecks()
        encodingChecks()
        externalChangeChecks()
        linkChecks()
        rowChecks()
        lineEndingChecks()
        try? FileManager.default.removeItem(at: scratch)
        if failed { print("selfcheck FAILED"); exit(1) }
        print("selfcheck passed")
        exit(0)
    }

    static func check(_ ok: Bool, _ label: String) {
        print(ok ? "ok - \(label)" : "FAIL - \(label)")
        if !ok { failed = true }
    }

    static func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return true
    }

    @MainActor static func shellChecks() {
        let key = "Aeris.SelfCheck.MainSplit"
        let defaultsKeys = ["NSSplitView Subview Frames \(key).Columns"]
        func clean() { defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        EditorWindowController.layoutKey = key
        clean()
        do {
            let wc = EditorWindowController()
            let items = wc.splitViewController.splitViewItems
            check(items.count == 4 && items[0].behavior == .sidebar, "shell: sidebar | list | editor | preview")
            check(items[0].viewController === wc.sidebar, "shell: sidebar pane is the SidebarViewController")
            check(wc.splitViewController.splitView.autosaveName == EditorWindowController.splitAutosaveName
                  && EditorWindowController.splitAutosaveName.hasPrefix(key), "shell: layout autosave name derives from layoutKey")
            let toggle = MainMenu.make().item(withTitle: "View")?.submenu?.item(withTitle: "Hide Library")
            check(toggle?.action == #selector(NSSplitViewController.toggleSidebar(_:))
                  && toggle?.keyEquivalent == "s" && toggle?.keyEquivalentModifierMask == [.command, .option],
                  "shell: View > Hide Library is ⌘⌥S")
            wc.splitViewController.toggleSidebar(nil)
            check(wait(timeout: 2) { wc.isSidebarCollapsed }, "shell: toggle collapses the sidebar")
            wc.splitViewController.toggleSidebar(nil)
            check(wait(timeout: 2) { !wc.isSidebarCollapsed }, "shell: toggle expands it again")
            wc.close()
        }
        clean()
    }

    /// The sidebar keeps its own width; the editor and preview share every other change.
    /// Needs real layout, so it forces it on the never-shown window's split view.
    @MainActor static func layoutChecks() {
        let key = "Aeris.SelfCheck.LayoutSplit"
        let defaultsKey = "NSSplitView Subview Frames \(key).Columns"
        let previousKey = EditorWindowController.layoutKey
        EditorWindowController.layoutKey = key
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey); EditorWindowController.layoutKey = previousKey }
        let wc = EditorWindowController()
        let split = wc.splitViewController.splitView
        func settle() { split.window?.contentView?.layoutSubtreeIfNeeded(); split.layoutSubtreeIfNeeded() }
        /// Sidebar, editor, preview (the file list holds its width and has its own checks).
        func widths() -> [CGFloat] { wc.splitViewController.splitViewItems.enumerated().filter { $0.offset != 1 }.map { $0.element.viewController.view.frame.width } }
        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat) -> Bool { abs(a - b) <= tol }
        settle()
        /// Waits until the pane widths stay the same across several settles (animation over), however loaded the machine is.
        func settled() {
            var last = widths(), stable = 0
            _ = wait(timeout: 10) {
                settle()
                let now = widths()
                stable = now == last ? stable + 1 : 0
                last = now
                return stable >= 5
            }
        }
        // A skewed layout (one pane much narrower than the other), the case H hit.
        split.setPosition(wc.splitViewController.splitViewItems[1].viewController.view.frame.maxX + split.dividerThickness + 330, ofDividerAt: 2)
        settle()
        let start = widths()
        check(start[0] > 100 && start[1] >= 299 && start[2] >= 299 && abs(start[1] - start[2]) > 0.8 * min(start[1], start[2]),
              "layout: the split view lays out headless, skewed (\(start.map { Int($0) }))")

        wc.splitViewController.toggleSidebar(nil)
        check(wait(timeout: 2) { wc.isSidebarCollapsed }, "layout: sidebar collapsed")
        settled()
        wc.splitViewController.toggleSidebar(nil)
        check(wait(timeout: 2) { !wc.isSidebarCollapsed }, "layout: sidebar expanded")
        settled()
        let after = widths()
        check(near(after[1], start[1], 2) && near(after[2], start[2], 2) && near(after[0], start[0], 2),
              "layout: collapse then expand restores editor and preview widths (\(start.map { Int($0) }) -> \(after.map { Int($0) }))")

        let frame = wc.window!.frame
        wc.window!.setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width + 200, height: frame.height), display: false)
        settle()
        let grown = widths()
        check(near(grown[0], after[0], 0.5), "layout: growing the window leaves the sidebar width alone (\(Int(after[0])) -> \(Int(grown[0])))")
        check(near(grown[1] / grown[2], after[1] / after[2], 0.02 * after[1] / after[2]) && grown[1] > after[1] && grown[2] > after[2],
              "layout: growing the window keeps the editor:preview ratio (\(Int(after[1])):\(Int(after[2])) -> \(Int(grown[1])):\(Int(grown[2])))")
        wc.window!.setFrame(frame, display: false)
        settle()
        let shrunk = widths()
        check(near(shrunk[0], after[0], 0.5) && near(shrunk[1] / shrunk[2], after[1] / after[2], 0.02 * after[1] / after[2]) && shrunk[1] < grown[1],
              "layout: shrinking the window back keeps the sidebar width and the ratio (\(grown.map { Int($0) }) -> \(shrunk.map { Int($0) }))")

        // Two quick presses of the toggle (collapse, expand; then expand, collapse) leave the split in proportion.
        let ratio = shrunk[1] / shrunk[2]
        // (Headless, AppKit drops a press that overlaps a running one, so the end state of a pair
        // isn't fixed; the ratio is what must hold, and the last step leaves the sidebar open.)
        func quickToggles(twice: Bool, _ label: String) {
            wc.splitViewController.toggleSidebar(nil)
            if twice { wc.splitViewController.toggleSidebar(nil) }
            settled()
            let w = widths()
            check(near(w[1] / w[2], ratio, 0.02 * ratio), "layout: \(label) keeps the editor:preview ratio (\(w.map { Int($0) }))")
        }
        quickToggles(twice: true, "two quick toggles")
        quickToggles(twice: false, "one more toggle")
        quickToggles(twice: true, "two quick toggles again")
        if wc.isSidebarCollapsed { quickToggles(twice: false, "expanding") }
        // (Headless, no overlapped pair ends open, so the overlap-only width restore can't be
        // observed here; and after one that ends collapsed, AppKit itself reopens at its minimum.)
        check(!wc.isSidebarCollapsed && near(widths()[1] / widths()[2], ratio, 0.02 * ratio),
              "layout: after the quick toggles the sidebar is open and the ratio is kept (\(widths().map { Int($0) }))")
        // A single toggle never forces an older sidebar width: drag it to 300 (no toggle), collapse
        // it (no toggle), expand with one toggle. The last toggle chain saw 220; that must not return.
        // (Headless, AppKit can leave the sidebar pinned at its last animated width after the toggles
        // above, ignoring the drag; a non-animated collapse and expand clears that.)
        wc.splitViewController.splitViewItems[0].isCollapsed = true
        settle()
        wc.splitViewController.splitViewItems[0].isCollapsed = false
        settled()
        split.setPosition(300, ofDividerAt: 0)
        settled()
        check(near(widths()[0], 300, 2), "layout: the sidebar divider moves to 300 without a toggle (\(Int(widths()[0])))")
        wc.splitViewController.splitViewItems[0].isCollapsed = true
        wc.splitViewController.splitViewItems[1].isCollapsed = true
        settled()
        wc.splitViewController.toggleSidebar(nil)
        settled()
        check(!wc.isSidebarCollapsed && !near(widths()[0], after[0], 2),
              "layout: a single expand does not force the sidebar back to an older width (\(Int(after[0])) -> \(Int(widths()[0])))")
        wc.close()
    }

    /// The location rows of a window's organizer, in order.
    @MainActor static func locationRows(_ wc: EditorWindowController) -> [LibraryNode] {
        let ov = wc.sidebar.outlineView
        return (0..<ov.numberOfRows).compactMap { ov.item(atRow: $0) as? LibraryNode }
    }

    /// Selects a location in the organizer as a click does, which fills the file list.
    @MainActor static func selectLocation(_ wc: EditorWindowController, _ node: LibraryNode) {
        let ov = wc.sidebar.outlineView
        ov.selectRowIndexes(IndexSet(integer: ov.row(forItem: node)), byExtendingSelection: false)
    }

    /// The names the file list shows.
    @MainActor static func listNames(_ wc: EditorWindowController) -> [String] {
        let list = wc.fileList
        return (0..<list.tableView.numberOfRows).compactMap { list.node(atRow: $0)?.name }
    }

    /// The row the file list highlights (the open document, or what the user selected).
    @MainActor static func highlighted(_ wc: EditorWindowController) -> URL? {
        wc.fileList.node(atRow: wc.fileList.tableView.selectedRow)?.url
    }

    /// Selects `url`'s row in the file list as a click does, bringing the list to its folder first.
    @MainActor static func selectInList(_ wc: EditorWindowController, _ url: URL) {
        let node = Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url))!
        wc.fileList.showFolder(node.parent)
        let row = (0..<wc.fileList.tableView.numberOfRows).first { wc.fileList.node(atRow: $0) === node }!
        wc.fileList.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    /// `docs/demo-library`, found by walking up from the executable, then from this source file,
    /// so the self-check runs from any working directory.
    static func demoLibrary() -> URL? {
        for start in [Bundle.main.executableURL, URL(fileURLWithPath: #filePath)].compactMap({ $0 }) {
            var dir = start.deletingLastPathComponent()
            while dir.path != "/" {
                let candidate = dir.appending(path: "docs/demo-library")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                dir = dir.deletingLastPathComponent()
            }
        }
        return nil
    }

    @MainActor static func libraryChecks() {
        guard let demo = demoLibrary() else {
            print("FAIL - library: docs/demo-library not found above the executable or the source file")
            exit(1)
        }
        let wc = EditorWindowController()
        wc.sidebar.loadViewIfNeeded()
        check(locationRows(wc).isEmpty, "sidebar: empty library has no location rows")
        Library.shared.addLocation(demo)
        check(locationRows(wc).count == 1, "sidebar: one row per location")
        selectLocation(wc, locationRows(wc)[0])
        check(listNames(wc) == ["Drafts", "Notes", "Welcome.md"], "sidebar: selecting a location lists its children in the file list")
        check(locationRows(wc).allSatisfy { $0.parent == nil }, "sidebar: the organizer shows locations, never their subfolders")
        let list = wc.fileList
        check(list.node(atRow: 0)!.isDirectory && !list.node(atRow: 2)!.isDirectory, "sidebar: the list tells folders from files")
        Library.shared.addLocation(demo)
        check(locationRows(wc).count == 1, "sidebar: adding the same folder twice is a no-op")
        let add = MainMenu.make().item(withTitle: "File")?.submenu?.item(withTitle: "Add Location…")
        check(add?.action == #selector(AppDelegate.addLocation(_:)) && add?.keyEquivalent == "", "sidebar: File > Add Location… exists")
        wc.close()
    }

    @MainActor static func persistenceChecks() {
        let fm = FileManager.default
        let folderA = scratch.appending(path: "PersistA"), folderB = scratch.appending(path: "PersistB")
        try? fm.createDirectory(at: folderA, withIntermediateDirectories: true)
        try? fm.createDirectory(at: folderB, withIntermediateDirectories: true)
        func relaunched() -> Library { Library(store: LocationStore(fileURL: LocationStore.defaultFileURL)) }
        let pathA = LibraryListing.canonicalPath(folderA)

        Library.shared.addLocation(folderA)
        check(relaunched().tree.roots.map(\.path).contains(pathA), "persist: location survives relaunch")
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
        check(relaunched().tree.roots.allSatisfy { $0.path != pathA }, "persist: removal survives relaunch")

        // A location whose folder vanished stays listed, dimmed, with "(missing)".
        let wc = EditorWindowController()
        wc.sidebar.loadViewIfNeeded()
        let ov = wc.sidebar.outlineView
        Library.shared.addLocation(folderB)
        let missingNode = Library.shared.tree.roots.last!
        try? fm.removeItem(at: folderB)
        Library.shared.reload()
        let row = ov.row(forItem: Library.shared.tree.roots.last!)
        check(row >= 0 && Library.shared.tree.roots.last !== missingNode, "persist: setup - the missing location has a row")
        let cell = ov.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
        check(cell?.textField?.stringValue == "PersistB (missing)" && cell?.textField?.textColor == .secondaryLabelColor,
              "persist: unresolvable location shows dimmed '(missing)'")
        check(relaunched().tree.roots.count == Library.shared.tree.roots.count, "persist: missing location kept in the store")

        let items = wc.sidebar.menuItems(forRow: row)
        check(items.map(\.title) == ["Remove from Library"] && items[0].tag == Library.shared.tree.roots.count - 1,
              "menu: location row offers Remove from Library")
        check(wc.sidebar.menuItems(forRow: 0).isEmpty && wc.sidebar.menuItems(forRow: -1).isEmpty,
              "menu: section rows and empty space offer nothing")
        let before = Library.shared.tree.roots.count
        _ = items[0].target?.perform(items[0].action, with: items[0])
        check(Library.shared.tree.roots.count == before - 1 && locationRows(wc).count == before - 1,
              "menu: Remove from Library removes the row")

        let folderC = scratch.appending(path: "PersistC")
        try? fm.createDirectory(at: folderC, withIntermediateDirectories: true)
        Library.shared.addLocation(folderC)
        let pathC = LibraryListing.canonicalPath(folderC)

        // A root-changed event rebuilds the watcher on the next turn, never inside the stream's callback.
        let watcherBefore = Library.shared.watcherForTesting
        Library.shared.folderChanged([FolderChange(path: pathC, mustScanSubDirs: false, rootChanged: true)])
        check(Library.shared.watcherForTesting === watcherBefore, "watch: root-changed does not rebuild the watcher synchronously")
        check(wait(timeout: 2) { Library.shared.watcherForTesting !== watcherBefore }, "watch: root-changed rebuilds the watcher afterwards")
        wc.close()
    }

    /// The organizer: its sections, hints and settings, and walking folders in the file list.
    @MainActor static func organizerChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else { return }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let previousKey = EditorWindowController.layoutKey
        let layout = "Aeris.SelfCheck.Organizer"
        EditorWindowController.layoutKey = layout
        let defaultsKeys = ["\(layout).CollapsedSections", "\(layout).HiddenSections"]
        func clean() { defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        clean()
        defer { clean(); EditorWindowController.layoutKey = previousKey }

        let loc = scratch.appending(path: "OrgLib")
        try? fm.createDirectory(at: loc.appending(path: "Sub/Deep"), withIntermediateDirectories: true)
        for name in ["top.md", "Sub/mid.md", "Sub/Deep/inner.md"] { try? name.write(to: loc.appending(path: name), atomically: true, encoding: .utf8) }
        func canonical(_ url: URL?) -> String? { url.map(LibraryListing.canonicalPath) }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: canonical(url)!)! }
        Library.shared.addLocation(loc)
        let rootsBefore = Library.shared.tree.roots.map(\.path)

        // A window opened after the location was added shows it, and adds nothing.
        let untitled = try! MarkdownDocument(type: "net.daringfireball.markdown")
        dc.addDocument(untitled); untitled.makeWindowControllers()
        let wc = untitled.windowControllers[0] as! EditorWindowController
        wc.sidebar.loadViewIfNeeded()
        let ov = wc.sidebar.outlineView
        func sections() -> [OrganizerSection] { (0..<ov.numberOfRows).compactMap { ov.item(atRow: $0) as? OrganizerSection } }
        func hints() -> [OrganizerHint] { (0..<ov.numberOfRows).compactMap { ov.item(atRow: $0) as? OrganizerHint } }
        check(Library.shared.tree.roots.map(\.path) == rootsBefore && locationRows(wc).map(\.path).contains(canonical(loc)!),
              "organizer: an existing location shows as a row, nothing re-added")
        check(sections().map(\.title) == ["Locations", "Favorites", "Smart Folders", "Tags"],
              "organizer: sections are Locations, Favorites, Smart Folders, Tags")
        check(sections().allSatisfy { ov.isItemExpanded($0) }, "organizer: sections start expanded")
        check(locationRows(wc).allSatisfy { $0.parent == nil }, "organizer: location rows are roots, never subfolders")

        // Empty sections show a hint.
        let hintRow = hints().first.map { ov.row(forItem: $0) } ?? -1
        let hintCell = hintRow >= 0 ? ov.view(atColumn: 0, row: hintRow, makeIfNecessary: true) as? NSTableCellView : nil
        check(hints().map(\.text) == ["Drop files or folders here", "Save a search to find it again here", "Type #tag in any file"]
              && hintCell?.textField?.stringValue == "Drop files or folders here",
              "organizer: each empty section shows its hint (\(hints().map(\.text)))")
        check(hints().allSatisfy { !wc.sidebar.outlineView(ov, shouldSelectItem: $0) }
              && sections().allSatisfy { !wc.sidebar.outlineView(ov, shouldSelectItem: $0) }
              && locationRows(wc).allSatisfy { wc.sidebar.outlineView(ov, shouldSelectItem: $0) },
              "organizer: only location rows can be selected")

        // Selecting a location fills the list; folders open in the list and ⌘↑ goes back up.
        selectLocation(wc, node(loc))
        let list = wc.fileList, table = list.tableView
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ chars: String = "") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        func selectRow(named name: String) { table.selectRowIndexes(IndexSet(integer: listNames(wc).firstIndex(of: name)!), byExtendingSelection: false) }
        check(list.folder === node(loc) && listNames(wc) == ["Sub", "top.md"], "organizer: selecting a location lists its contents (\(listNames(wc)))")
        check(!list.upButton.isEnabled, "organizer: no way up from a location")
        table.keyDown(with: key(126, .command))
        check(list.folder === node(loc), "organizer: ⌘↑ at a location does nothing")
        selectRow(named: "top.md")
        table.keyDown(with: key(36, [], "\r"))
        check(list.folder === node(loc), "organizer: Return on a file does not navigate")
        selectRow(named: "Sub")
        table.sendAction(table.doubleAction, to: table.target)
        check(list.folder === node(loc.appending(path: "Sub")) && listNames(wc) == ["Deep", "mid.md"] && list.titleLabel.stringValue == "Sub"
              && list.upButton.isEnabled, "organizer: double-clicking a folder opens it in the list")
        selectRow(named: "Deep")
        table.keyDown(with: key(36, [], "\r"))
        check(list.folder === node(loc.appending(path: "Sub/Deep")) && listNames(wc) == ["inner.md"], "organizer: Return on a folder opens it")
        check(canonical(wc.sidebar.selectedURL) == canonical(loc), "organizer: the organizer stays on the location while the list goes down")
        table.keyDown(with: key(126, .command))
        check(list.folder === node(loc.appending(path: "Sub")) && list.node(atRow: table.selectedRow)?.name == "Deep",
              "organizer: ⌘↑ goes back up and selects the folder it came from")
        // The arrow onto top.md above opened it in this window, so going up into its folder highlights it.
        list.upButton.performClick(nil)
        check(list.folder === node(loc) && (wc.document as? NSDocument)?.fileURL?.lastPathComponent == "top.md"
              && highlighted(wc)?.lastPathComponent == "top.md",
              "organizer: the up button goes back up and highlights the open document there (\(listNames(wc)), row \(table.selectedRow))")
        selectRow(named: "Sub")
        table.keyDown(with: key(36, [], "\r"))
        check(wc.sidebar.outlineView.target === wc.sidebar && wc.sidebar.outlineView.action != nil,
              "organizer: a click on the organizer reaches it")
        wc.sidebar.locationClicked(row: ov.row(forItem: node(loc)))
        check(list.folder === node(loc), "organizer: clicking the selected location brings the list back to its top")

        // Revealing a document in a subfolder: location in the organizer, folder and row in the list.
        let inner = try! dc.makeDocument(withContentsOf: loc.appending(path: "Sub/Deep/inner.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(inner); inner.makeWindowControllers()
        let wcInner = inner.windowControllers[0] as! EditorWindowController
        check(canonical(wcInner.sidebar.selectedURL) == canonical(loc) && wcInner.fileList.folder === node(loc.appending(path: "Sub/Deep"))
              && highlighted(wcInner)?.lastPathComponent == "inner.md",
              "organizer: revealing a document selects its location and its row in the list")
        wcInner.close(); inner.close()

        // Collapsing a section is remembered, and sections start expanded in a fresh window.
        let tags = sections().first { $0.kind == .tags }!
        ov.collapseItem(tags)
        check(UserDefaults.standard.stringArray(forKey: defaultsKeys[0]) == ["tags"] && hints().count == 2, "organizer: collapsing Tags is saved")
        let wc2 = EditorWindowController()
        wc2.sidebar.loadViewIfNeeded()
        let ov2 = wc2.sidebar.outlineView
        let sections2 = (0..<ov2.numberOfRows).compactMap { ov2.item(atRow: $0) as? OrganizerSection }
        check(sections2.map { ov2.isItemExpanded($0) } == [true, true, true, false], "organizer: a new window restores the collapsed Tags")
        ov.expandItem(tags)
        check((UserDefaults.standard.stringArray(forKey: defaultsKeys[0]) ?? []).isEmpty, "organizer: expanding Tags again is saved")
        wc2.close()

        // Revealing a document expands a collapsed Locations without forgetting the collapse.
        let locations = sections().first { $0.kind == .locations }!
        ov.collapseItem(locations)
        wc.sidebar.reveal(loc.appending(path: "top.md"))
        check(UserDefaults.standard.stringArray(forKey: defaultsKeys[0]) == ["locations"],
              "organizer: revealing into a collapsed Locations keeps the collapse saved")
        UserDefaults.standard.removeObject(forKey: defaultsKeys[0])
        ov.expandItem(locations)

        // Hiding sections: the View > Organizer submenu, live in open windows, kept for new ones.
        let organizerMenu = MainMenu.make().item(withTitle: "View")?.submenu?.item(withTitle: "Organizer")?.submenu
        check(organizerMenu?.items.map(\.title) == ["Favorites", "Smart Folders", "Tags"], "organizer: View > Organizer lists the three hideable sections")
        let smart = organizerMenu!.item(withTitle: "Smart Folders")!
        let appDelegate = NSApp.delegate as! AppDelegate
        check(appDelegate.validateMenuItem(smart) && smart.state == .on, "organizer: a shown section is checked in the menu")
        check(NSApp.sendAction(smart.action!, to: nil, from: smart), "organizer: the menu item reaches the app")
        check(sections().map(\.title) == ["Locations", "Favorites", "Tags"] && hints().count == 2, "organizer: hiding Smart Folders removes the section")
        check(UserDefaults.standard.stringArray(forKey: defaultsKeys[1]) == ["smartFolders"], "organizer: the hidden section is stored")
        _ = appDelegate.validateMenuItem(smart)
        check(smart.state == .off, "organizer: a hidden section is unchecked in the menu")
        let wc3 = EditorWindowController()
        wc3.sidebar.loadViewIfNeeded()
        let ov3 = wc3.sidebar.outlineView
        check((0..<ov3.numberOfRows).compactMap { (ov3.item(atRow: $0) as? OrganizerSection)?.title } == ["Locations", "Favorites", "Tags"],
              "organizer: a new window keeps Smart Folders hidden")
        wc3.close()
        _ = NSApp.sendAction(smart.action!, to: nil, from: smart)
        check(sections().map(\.title) == ["Locations", "Favorites", "Smart Folders", "Tags"]
              && (UserDefaults.standard.stringArray(forKey: defaultsKeys[1]) ?? []).isEmpty, "organizer: enabling it again brings the section back")
        let wc4 = EditorWindowController()
        wc4.sidebar.loadViewIfNeeded()
        check(wc4.sidebar.outlineView.numberOfRows == ov.numberOfRows, "organizer: and a new window shows it")
        wc4.close()

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "organizer: no window was ordered in")
        (wc.document as? NSDocument)?.close()
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// The file list column: filled from the sidebar's folder, opens files (click focuses the
    /// editor, arrow keys keep focus in the list), follows disk changes; the two hide commands
    /// and the widths and hidden states persist.
    @MainActor static func columnChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else { return }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let previousKey = EditorWindowController.layoutKey
        EditorWindowController.layoutKey = "Aeris.SelfCheck.ColumnSplit"
        let defaultsKey = "NSSplitView Subview Frames \(EditorWindowController.splitAutosaveName)"
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            EditorWindowController.layoutKey = previousKey
        }
        let loc = scratch.appending(path: "ColumnLib")
        try? fm.createDirectory(at: loc.appending(path: "sub"), withIntermediateDirectories: true)
        let urlA = loc.appending(path: "A.md"), urlB = loc.appending(path: "B.md"), urlC = loc.appending(path: "sub/C.md")
        for (url, text) in [(urlA, "alpha"), (urlB, "beta"), (urlC, "gamma")] { try? text.write(to: url, atomically: true, encoding: .utf8) }
        func canonical(_ url: URL?) -> String? { url.map(LibraryListing.canonicalPath) }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: canonical(url)!)! }
        Library.shared.addLocation(loc)

        let a = try! dc.makeDocument(withContentsOf: urlA, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(a); a.makeWindowControllers()
        let wc = a.windowControllers[0] as! EditorWindowController
        let list = wc.fileList, table = list.tableView
        let split = wc.splitViewController
        func names() -> [String] { (0..<table.numberOfRows).map { list.node(atRow: $0)!.name } }
        func openURL() -> String? { canonical((wc.document as? NSDocument)?.fileURL) }
        func rowOf(_ url: URL) -> Int { names().firstIndex(of: url.lastPathComponent)! }
        func select(row: Int) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        func collapsed(_ s: NSSplitViewController) -> [Bool] { s.splitViewItems.map(\.isCollapsed) }
        check(split.splitViewItems.count == 4 && split.splitViewItems[1].viewController === list,
              "columns: sidebar | list | editor | preview")

        // Selecting a folder in the sidebar lists its children.
        selectLocation(wc, node(loc))
        let children = node(loc).children!.map(\.name)
        check(list.folder === node(loc) && names() == children && children.contains("A.md") && children.contains("sub"),
              "columns: selecting a folder lists its files and subfolders (\(names()))")
        check(list.titleLabel.stringValue == "ColumnLib", "columns: the title shows the folder name")

        // Click: opens, and the editor takes the keyboard.
        wc.window!.makeFirstResponder(table)
        select(row: rowOf(urlB))
        table.sendAction(table.action, to: table.target)
        check(wait(timeout: 3) { openURL() == canonical(urlB) } && wc.window!.firstResponder === editorTextView(wc),
              "columns: clicking a file row opens it and the editor is first responder")
        // Arrow keys: each row opens, the list keeps the keyboard; a folder row opens nothing.
        wc.window!.makeFirstResponder(table)
        select(row: rowOf(urlA))
        check(wait(timeout: 3) { openURL() == canonical(urlA) } && wc.window!.firstResponder === table,
              "columns: moving to the next file opens it and the list keeps focus")
        select(row: rowOf(loc.appending(path: "sub")))
        _ = wait(timeout: 0.3) { false }
        check(openURL() == canonical(urlA) && wc.window!.firstResponder === table, "columns: a folder row opens nothing")

        // Live refresh reaches the list.
        let urlD = loc.appending(path: "D.md")
        try? "delta".write(to: urlD, atomically: true, encoding: .utf8)
        Library.shared.folderChanged([FolderChange(path: canonical(loc)!, mustScanSubDirs: false, rootChanged: false)])
        check(names().contains("D.md"), "columns: a file created on disk appears in the list")
        try? fm.removeItem(at: urlD)
        Library.shared.folderChanged([FolderChange(path: canonical(loc)!, mustScanSubDirs: false, rootChanged: false)])
        check(!names().contains("D.md"), "columns: a file deleted on disk leaves the list")

        // A file created or deleted above the highlighted row: the highlight and what it opens stay on that file.
        let realOpen = list.onOpen
        var opened: [String?] = []
        list.onOpen = { url, _ in opened.append(canonical(url)) }
        func refresh() { Library.shared.folderChanged([FolderChange(path: canonical(loc)!, mustScanSubDirs: false, rootChanged: false)]) }
        func opensHighlighted(_ url: URL) -> Bool {
            opened = []
            table.sendAction(table.action, to: table.target)
            list.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: table))
            return opened == [canonical(url), canonical(url)]
        }
        let urlAB = loc.appending(path: "AB.md")
        list.reveal(urlB)
        try? "ab".write(to: urlAB, atomically: true, encoding: .utf8)
        refresh()
        check(names().firstIndex(of: "AB.md").map { $0 < rowOf(urlB) } == true && canonical(highlighted(wc)) == canonical(urlB),
              "columns: a file created above the highlighted row keeps the highlight on it")
        check(opensHighlighted(urlB), "columns: after a create above it, click and arrow open the highlighted file (\(opened))")
        try? fm.removeItem(at: urlAB)
        refresh()
        check(!names().contains("AB.md") && canonical(highlighted(wc)) == canonical(urlB),
              "columns: a file deleted above the highlighted row keeps the highlight on it")
        check(opensHighlighted(urlB), "columns: after a delete above it, click and arrow open the highlighted file (\(opened))")

        // The highlighted file deleted or renamed away: nothing stays highlighted.
        let urlE = loc.appending(path: "E.md"), urlF = loc.appending(path: "F.md")
        try? "epsilon".write(to: urlE, atomically: true, encoding: .utf8)
        refresh()
        list.reveal(urlE)
        try? fm.moveItem(at: urlE, to: urlF)
        refresh()
        check(names().contains("F.md") && table.selectedRow == -1, "columns: renaming the highlighted file away clears the highlight")
        list.reveal(urlF)
        try? fm.removeItem(at: urlF)
        refresh()
        check(!names().contains("F.md") && table.selectedRow == -1, "columns: deleting the highlighted file clears the highlight")
        list.onOpen = realOpen

        // Hiding: Hide Organizer keeps the list and editor; ⌘⌥S hides the list with the organizer.
        let menu = MainMenu.make().item(withTitle: "View")?.submenu
        check(menu?.item(withTitle: "Hide Library")?.keyEquivalent == "s"
              && menu?.item(withTitle: "Hide Library")?.keyEquivalentModifierMask == [.command, .option]
              && menu?.item(withTitle: "Hide Organizer")?.action == #selector(LibrarySplitViewController.toggleOrganizer(_:)),
              "columns: View menu has Hide Library (⌘⌥S) and Hide Organizer")
        split.toggleOrganizer(nil)
        check(wait(timeout: 2) { collapsed(split) == [true, false, false, false] }, "columns: Hide Organizer hides only the left column")
        split.toggleSidebar(nil)
        check(wait(timeout: 2) { collapsed(split) == [true, true, false, false] }, "columns: ⌘⌥S with the list showing hides organizer and list")
        split.toggleSidebar(nil)
        check(wait(timeout: 2) { collapsed(split) == [false, false, false, false] }, "columns: ⌘⌥S again shows both")

        // Widths and hidden states restore in a new window.
        // A saved layout (AppKit's own autosave record: x, y, width, height, collapsed, hidden per
        // column) is restored by a new window. Headless, AppKit does not write that record for
        // programmatic changes, so it is seeded here; that AppKit writes it on a real drag or
        // collapse is checked on screen.
        func widths(_ s: NSSplitViewController) -> [CGFloat] { s.splitViewItems.map { $0.viewController.view.frame.width } }
        func seed(_ columns: [(width: Int, collapsed: Bool)]) {
            var x = 0
            UserDefaults.standard.set(columns.map { c in
                defer { x += c.width + 1 }
                return "\(x).000000, 0.000000, \(c.width).000000, 736.000000, \(c.collapsed ? "YES" : "NO"), NO"
            }, forKey: defaultsKey)
        }
        wc.close(); a.close()
        func reopen() -> EditorWindowController {
            let d = try! dc.makeDocument(withContentsOf: urlA, ofType: "net.daringfireball.markdown") as! MarkdownDocument
            dc.addDocument(d); d.makeWindowControllers()
            let w = d.windowControllers[0] as! EditorWindowController
            w.window?.contentView?.layoutSubtreeIfNeeded(); w.splitViewController.view.layoutSubtreeIfNeeded()
            return w
        }
        seed([(220, true), (300, false), (500, false), (517, false)])
        let wc2 = reopen()
        let hidden = widths(wc2.splitViewController)
        check(collapsed(wc2.splitViewController) == [true, false, false, false], "columns: a new window restores the hidden organizer")
        check(abs(hidden[1] - 300) <= 3 && abs(hidden[2] - 500) <= 3,
              "columns: a new window restores the list and editor widths (\(hidden.map { Int($0) }))")
        let doc2 = wc2.document as! NSDocument
        wc2.close(); doc2.close()
        seed([(240, false), (300, false), (400, false), (377, false)])
        let wc3 = reopen()
        let shown = widths(wc3.splitViewController)
        check(collapsed(wc3.splitViewController) == [false, false, false, false]
              && zip(shown, [240, 300, 400]).allSatisfy { abs($0 - $1) <= 3 },
              "columns: a shown organizer restores its width (\(shown.map { Int($0) }))")
        let doc3 = wc3.document as! NSDocument
        wc3.close(); doc3.close()
        check(NSApp.windows.allSatisfy { !$0.isVisible }, "columns: no window was ordered in")
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// Stands in for NSDocument's save sheet: holds the `canClose` answer until told. A real
    /// sheet orders its never-shown parent window onto the screen (AppKit does this), which
    /// the self-check must never do; the real sheet is checked on screen.
    final class HeldCloseDocument: MarkdownDocument {
        var answer: ((Bool) -> Void)?

        override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                               contextInfo: UnsafeMutableRawPointer?) {
            guard let target = delegate as? NSObject, let selector = shouldCloseSelector else { return }
            answer = { [unowned self] ok in
                typealias ShouldClose = @convention(c) (NSObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(target.method(for: selector), to: ShouldClose.self)(target, selector, self, ok, contextInfo)
            }
        }
    }

    /// M1-12: in a CRLF document, Return, list continuation and a paste of LF text all
    /// insert CRLF; an LF document stays LF. Existing endings are never converted.
    @MainActor static func lineEndingChecks() {
        let dir = scratch.appending(path: "LineEndings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let board = NSPasteboard(name: NSPasteboard.Name("aeris-selfcheck-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        for (name, eol) in [("crlf.md", "\r\n"), ("lf.md", "\n")] {
            let url = dir.appending(path: name)
            try? Data("# Title\(eol)\(eol)- a".utf8).write(to: url)
            let dc = NSDocumentController.shared
            guard let doc = try? dc.makeDocument(withContentsOf: url, ofType: "net.daringfireball.markdown")
                    as? MarkdownDocument else { check(false, "line endings: \(name) opens"); continue }
            dc.addDocument(doc); doc.makeWindowControllers()
            let wc = doc.windowControllers[0] as! EditorWindowController
            let tv = editorTextView(wc)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))   // list continuation: "- "
            tv.insertText("b", replacementRange: tv.selectedRange())
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))   // continuation again
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))   // empty item: clears the line
            tv.insertText("plain", replacementRange: tv.selectedRange())
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))   // plain Return
            board.clearContents()
            board.setString(eol == "\n" ? "p1\r\np2\rp3\n" : "p1\np2\rp3\n", forType: .string)
            tv.readSelection(from: board, type: .string)                  // paste of foreign endings
            var saved = false
            doc.save(to: url, ofType: doc.fileType!, for: .saveOperation) { saved = $0 == nil }
            _ = wait(timeout: 3) { saved }
            let bytes = [UInt8]((try? Data(contentsOf: url)) ?? Data())
            let text = String(decoding: bytes, as: UTF8.self)
            let breaks = text.utf16.filter { $0 == 0x0A }.count
            let crs = bytes.filter { $0 == 0x0D }.count
            let consistent = eol == "\r\n"
                ? crs == breaks && !text.replacingOccurrences(of: "\r\n", with: "").contains(where: { $0 == "\r" || $0 == "\n" })
                : crs == 0
            let expected = ["# Title", "", "- a", "- b", "plain", "p1", "p2", "p3", ""].joined(separator: eol)
            check(saved && consistent && text == expected,
                  "line endings: \(name) stays \(eol == "\n" ? "LF" : "CRLF") after Return, list continuation and paste"
                  + (consistent && text == expected ? "" : " (got \(text.debugDescription))"))
            doc.close()
        }

        // A mixed file keeps its existing endings; new lines follow its first one.
        let mixed = dir.appending(path: "mixed.md")
        try? Data("a\r\nb\nc".utf8).write(to: mixed)
        if let doc = try? NSDocumentController.shared.makeDocument(withContentsOf: mixed, ofType: "net.daringfireball.markdown")
            as? MarkdownDocument {
            NSDocumentController.shared.addDocument(doc); doc.makeWindowControllers()
            let tv = editorTextView(doc.windowControllers[0] as! EditorWindowController)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            tv.insertText("d", replacementRange: tv.selectedRange())
            var saved = false
            doc.save(to: mixed, ofType: doc.fileType!, for: .saveOperation) { saved = $0 == nil }
            _ = wait(timeout: 3) { saved }
            check(saved && (try? Data(contentsOf: mixed)) == Data("a\r\nb\nc\r\nd".utf8),
                  "line endings: a mixed file keeps its endings; Return inserts its first (CRLF)")
            doc.close()
        } else {
            check(false, "line endings: mixed.md opens")
        }

        // A paste over two selections (Option-drag) is AppKit's multi-range change: the
        // first range gets the text, the second is emptied. Converting the first part
        // would shift the second range onto the wrong text, so it is left as AppKit does it.
        let multi = dir.appending(path: "multi.md")
        try? Data("foo\r\nmid\nfoo".utf8).write(to: multi)
        if let doc = try? NSDocumentController.shared.makeDocument(withContentsOf: multi, ofType: "net.daringfireball.markdown")
            as? MarkdownDocument {
            NSDocumentController.shared.addDocument(doc); doc.makeWindowControllers()
            let tv = editorTextView(doc.windowControllers[0] as! EditorWindowController)
            tv.selectedRanges = [NSValue(range: NSRange(location: 0, length: 3)), NSValue(range: NSRange(location: 9, length: 3))]
            board.clearContents()
            board.setString("x\ny", forType: .string)
            tv.readSelection(from: board, type: .string)
            var saved = false
            doc.save(to: multi, ofType: doc.fileType!, for: .saveOperation) { saved = $0 == nil }
            _ = wait(timeout: 3) { saved }
            let disk = (try? Data(contentsOf: multi)) ?? Data()
            check(saved && disk == Data("x\ny\r\nmid\n".utf8),
                  "line endings: a paste over two selections keeps the text between them"
                  + (disk == Data("x\ny\r\nmid\n".utf8) ? "" : " (got \(String(decoding: disk, as: UTF8.self).debugDescription))"))
            doc.close()
        } else {
            check(false, "line endings: multi.md opens")
        }

        // Changes AppKit makes itself (Replace All, Transformations) are never converted
        // when they span several ranges or replace existing line breaks.
        func edit(_ name: String, _ text: String, _ body: (NSTextView) -> Void) -> String? {
            let url = dir.appending(path: name)
            try? Data(text.utf8).write(to: url)
            guard let doc = try? NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: "net.daringfireball.markdown")
                    as? MarkdownDocument else { return nil }
            NSDocumentController.shared.addDocument(doc); doc.makeWindowControllers()
            let tv = editorTextView(doc.windowControllers[0] as! EditorWindowController)
            body(tv)
            let out = tv.string
            doc.close()
            return out
        }
        // Replace All: one multi-range change, applied as NSTextView applies it.
        let replaced = edit("replace.md", "ab\r\nab") { tv in
            let ranges = [NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)]
            guard tv.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                                      replacementStrings: ["x\ny", "x\ny"]) else { return }
            for r in ranges.reversed() { tv.textStorage?.replaceCharacters(in: r, with: "x\ny") }
            tv.didChangeText()
        }
        func got(_ s: String?, _ want: String) -> String { s == want ? "" : " (got \(s.debugDescription))" }
        check(replaced == "x\ny\r\nx\ny", "line endings: Replace All over two ranges replaces exactly those"
              + got(replaced, "x\ny\r\nx\ny"))
        let upper = edit("upper.md", "aa\r\nbb\ncc dd ee ff") { tv in
            tv.selectedRanges = [NSRange(location: 0, length: 5), NSRange(location: 5, length: 3),
                                 NSRange(location: 13, length: 5)].map { NSValue(range: $0) }
            tv.uppercaseWord(nil)
        }
        check(upper == "AA\r\nBB\nCC dd EE FF", "line endings: Make Upper Case over three selections changes only letters"
              + got(upper, "AA\r\nBB\nCC dd EE FF"))
        let mixedUpper = edit("upper1.md", "aa\r\nbb\ncc") { tv in
            tv.setSelectedRange(NSRange(location: 0, length: 9))
            tv.uppercaseWord(nil)
        }
        check(mixedUpper == "AA\r\nBB\nCC", "line endings: Make Upper Case over a mixed range keeps its endings"
              + got(mixedUpper, "AA\r\nBB\nCC"))
    }

    @MainActor static func editorTextView(_ wc: EditorWindowController) -> NSTextView { wc.editorForTesting.textViewForTesting }

    /// Open a non-UTF-8 file, edit, save: same encoding, same bytes outside the edit,
    /// and a save that can't be encoded fails instead of dropping characters.
    @MainActor static func encodingChecks() {
        let dir = scratch.appending(path: "Encoding")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func charset(_ url: URL) -> String {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/file")
            p.arguments = ["-b", "-I", url.path]
            p.standardOutput = pipe
            try? p.run(); p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return out.components(separatedBy: "charset=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func open(_ url: URL) -> MarkdownDocument? {
            try? NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: "net.daringfireball.markdown")
                as? MarkdownDocument
        }
        /// Saves in place (or to `url` with `op`); nil when the save didn't finish in time.
        func save(_ doc: MarkdownDocument, to url: URL? = nil,
                  _ op: NSDocument.SaveOperationType = .saveOperation) -> Result<Void, Error>? {
            var result: Result<Void, Error>?
            doc.save(to: url ?? doc.fileURL!, ofType: doc.fileType!, for: op) { error in
                result = error.map { .failure($0) } ?? .success(())
            }
            _ = wait(timeout: 3) { result != nil }
            return result
        }
        func succeeded(_ r: Result<Void, Error>?) -> Bool { if case .success = r { true } else { false } }
        func insert(_ text: String, in doc: MarkdownDocument) {
            doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }

        // Latin-1 text with accents and CRLF line endings.
        let latin1 = dir.appending(path: "latin1.md")
        let original = Data([0x4E, 0x6F, 0xEB, 0x6C, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A, 0x78, 0x0A])
        try? original.write(to: latin1)
        let before = charset(latin1)
        let doc = open(latin1)
        check(doc?.textStorage.string == "Noël café\r\nx\n" && doc?.encoding == .windows1252,
              "encoding: a Latin-1 file opens with the correct text")
        if let doc {
            insert("Hé ", in: doc)
            let saved = succeeded(save(doc))
            let disk = try? Data(contentsOf: latin1)
            check(saved && disk == Data([0x48, 0xE9, 0x20]) + original,
                  "encoding: after edit + save, bytes outside the edit are unchanged")
            check(before == "iso-8859-1" && charset(latin1) == before, "encoding: `file -I` still reports \(before)")

            insert("👋", in: doc)
            var failure: Error?
            if case .failure(let e) = save(doc) { failure = e }
            check((failure as? CocoaError)?.code == .fileWriteInapplicableStringEncoding
                  && (try? Data(contentsOf: latin1)) == disk,
                  "encoding: an emoji in a Windows-1252 file fails the save and leaves the file untouched")
            doc.close()
        }

        // UTF-8 with a BOM keeps it; UTF-8 without one doesn't gain one.
        for (name, bom) in [("bom.md", true), ("plain.md", false)] {
            let url = dir.appending(path: name)
            let mark = bom ? Data([0xEF, 0xBB, 0xBF]) : Data()
            try? (mark + Data("café".utf8)).write(to: url)
            guard let d = open(url) else { check(false, "encoding: \(name) opens"); continue }
            insert("x", in: d)
            check(succeeded(save(d)) && (try? Data(contentsOf: url)) == mark + Data("xcafé".utf8),
                  "encoding: UTF-8 \(bom ? "keeps its BOM" : "gains no BOM") after save")
            d.close()
        }

        // The first edit the encoding can't store asks once; Keep stops asking until the
        // text is storable again. (The seam answers; no alert is ever shown here.)
        let cafe = Data([0x63, 0x61, 0x66, 0xE9])  // "café" in Windows-1252
        let askURL = dir.appending(path: "ask.md")
        try? cafe.write(to: askURL)
        if let d = open(askURL) {
            encodingAsks = []
            insert("😀", in: d)
            check(wait(timeout: 2) { encodingAsks.count == 1 } && encodingAsks.first == "😀",
                  "encoding: an emoji in a Windows-1252 document asks once, naming the emoji")
            insert("é😀", in: d)
            check(!wait(timeout: 0.3) { encodingAsks.count > 1 } && d.encoding == .windows1252,
                  "encoding: after Keep, further emoji don't ask again and nothing converts")
            d.textStorage.replaceCharacters(in: NSRange(location: 0, length: d.textStorage.length), with: "ok")
            insert("😀", in: d)
            check(wait(timeout: 2) { encodingAsks.count == 2 }, "encoding: once storable again, the next emoji asks again")
            d.close()
        }

        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            check(false, "encoding: close checks skipped, 'Ask to keep changes when closing documents' is on")
            return
        }
        /// Asks the document whether it can close, as the window's close button does.
        func canClose(_ doc: NSDocument) -> Bool? {
            let probe = CloseProbe()
            doc.canClose(withDelegate: probe, shouldClose: #selector(CloseProbe.document(_:shouldClose:contextInfo:)),
                         contextInfo: nil)
            _ = wait(timeout: 3) { probe.answer != nil }
            return probe.answer
        }
        func isUTF8(_ url: URL, _ text: String) -> Bool { (try? Data(contentsOf: url)) == Data(text.utf8) }

        // Kept encoding + emoji: close refuses (error cancelled) and the file is untouched;
        // Convert to UTF-8 makes close save and proceed.
        let keepURL = dir.appending(path: "keep.md")
        try? cafe.write(to: keepURL)
        if let d = try? ErrorAnsweringDocument(contentsOf: keepURL, ofType: "net.daringfireball.markdown") {
            insert("😀", in: d)
            _ = wait(timeout: 2) { !encodingAsks.isEmpty }
            d.updateChangeCount(.changeDone)
            check(canClose(d) == false && (try? Data(contentsOf: keepURL)) == cafe,
                  "encoding: kept Windows-1252 + emoji: close is refused and the file is unchanged")
            let error = d.presented.last as NSError?
            // NSDocument wraps the error ("could not be autosaved"); the sheet shows our suggestion.
            check(error?.localizedRecoverySuggestion?.contains("Western (Windows Latin 1)") == true
                  && error?.localizedRecoveryOptions?.first == "Save as UTF-8",
                  "encoding: the save error names the encoding and offers Save as UTF-8")
            d.convertToUTF8()
            check(canClose(d) == true && isUTF8(keepURL, "😀café"),
                  "encoding: after Convert to UTF-8, close saves valid UTF-8 with the emoji")
            d.close()
        }

        // The error's "Save as UTF-8" recovery converts but counts as not saved: the close
        // that hit the error stays open, and the next close writes UTF-8 and proceeds.
        let recoverURL = dir.appending(path: "recover.md")
        try? cafe.write(to: recoverURL)
        if let d = try? ErrorAnsweringDocument(contentsOf: recoverURL, ofType: "net.daringfireball.markdown") {
            d.recoveryOption = 0
            insert("😀", in: d)
            _ = wait(timeout: 2) { !encodingAsks.isEmpty }
            d.updateChangeCount(.changeDone)
            check(canClose(d) == false && d.encoding == .utf8 && d.isDocumentEdited
                  && (try? Data(contentsOf: recoverURL)) == cafe,
                  "encoding: Save as UTF-8 in the close error converts, keeps the document edited, doesn't close")
            check(canClose(d) == true && isUTF8(recoverURL, "😀café"),
                  "encoding: the next close writes UTF-8 with the emoji and proceeds")
            d.close()
        }

        // ⌘S, error, "Save as UTF-8": NSDocument must not count that as saved (else Quit
        // would leave the old bytes); the document stays edited and the next save writes UTF-8.
        let cmdSURL = dir.appending(path: "cmd-s.md")
        try? cafe.write(to: cmdSURL)
        if let d = try? ErrorAnsweringDocument(contentsOf: cmdSURL, ofType: "net.daringfireball.markdown") {
            d.recoveryOption = 0
            insert("😀", in: d)
            _ = wait(timeout: 2) { !encodingAsks.isEmpty }
            d.updateChangeCount(.changeDone)
            d.save(withDelegate: nil, didSave: nil, contextInfo: nil)
            _ = wait(timeout: 3) { !d.presented.isEmpty }
            _ = wait(timeout: 0.3) { false }
            check(!d.presented.isEmpty && d.isDocumentEdited && d.hasUnautosavedChanges
                  && (try? Data(contentsOf: cmdSURL)) == cafe,
                  "encoding: after ⌘S + Save as UTF-8 the document is still edited (nothing claimed saved)")
            check(succeeded(save(d)) && isUTF8(cmdSURL, "😀café"), "encoding: the next save writes UTF-8 with the emoji")
            d.close()
        }

        // An autosave to the document's own file during a Save As elsewhere keeps the file's
        // encoding: the encoding is decided per write, not per document.
        let ownURL = dir.appending(path: "own.md"), otherURL = dir.appending(path: "other.md")
        let nestedURL = dir.appending(path: "own-autosave.md")
        try? cafe.write(to: ownURL)
        if let d = try? NestedWriteDocument(contentsOf: ownURL, ofType: "net.daringfireball.markdown") {
            d.nestedURL = nestedURL
            _ = save(d, to: otherURL, .saveAsOperation)
            check(isUTF8(otherURL, "café") && (try? Data(contentsOf: nestedURL)) == cafe,
                  "encoding: an in-place autosave overlapping a Save As still writes Windows-1252")
            d.close()
        }

        // Save As always writes UTF-8 to the new file and never touches the original.
        let asURL = dir.appending(path: "as-source.md"), asTarget = dir.appending(path: "as-target.md")
        try? cafe.write(to: asURL)
        if let d = open(asURL) {
            check(succeeded(save(d, to: asTarget, .saveAsOperation)) && isUTF8(asTarget, "café")
                  && (try? Data(contentsOf: asURL)) == cafe && d.encoding == .utf8,
                  "encoding: Save As writes UTF-8, leaves the original's bytes unchanged, document is now UTF-8")
            d.close()
        }
    }

    /// Examples passed to `MarkdownDocument.askToConvert` during the self-check.
    nonisolated(unsafe) static var encodingAsks: [String] = []

    final class CloseProbe: NSObject {
        var answer: Bool?
        @objc func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            answer = shouldClose
        }
    }

    /// During its Save As write, also performs an in-place autosave write (to `nestedURL`,
    /// standing in for the original file), as an overlapping autosave would.
    final class NestedWriteDocument: MarkdownDocument {
        nonisolated(unsafe) var nestedURL: URL?
        override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                            originalContentsURL: URL?) throws {
            if saveOperation == .saveAsOperation, let nested = nestedURL {
                nestedURL = nil
                try write(to: nested, ofType: typeName, for: .autosaveInPlaceOperation, originalContentsURL: fileURL)
            }
            try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: originalContentsURL)
        }
    }

    /// Stands in for the user at the error sheet: records each error, then picks
    /// `recoveryOption` (nil = Cancel), so no sheet or alert is shown.
    final class ErrorAnsweringDocument: MarkdownDocument {
        var recoveryOption: Int?
        var presented: [Error] = []

        override func presentError(_ error: Error, modalFor window: NSWindow, delegate: Any?,
                                   didPresent selector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
            presented.append(error)
            if let option = recoveryOption, let attempter = (error as NSError).recoveryAttempter as? NSObject {
                attempter.attemptRecovery(fromError: error, optionIndex: option, delegate: delegate,
                                          didRecoverSelector: selector, contextInfo: contextInfo)
            } else if let target = delegate as? NSObject, let selector {
                typealias DidPresent = @convention(c) (NSObject, Selector, Bool, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(target.method(for: selector), to: DidPresent.self)(target, selector, false, contextInfo)
            }
        }

        override func presentError(_ error: Error) -> Bool {
            presented.append(error)
            guard let option = recoveryOption, let attempter = (error as NSError).recoveryAttempter as? NSObject
            else { return false }
            return attempter.attemptRecovery(fromError: error, optionIndex: option)
        }
    }

    static func editorState(at url: URL) -> EditorState? {
        ExtendedAttributes.data(named: EditorState.attributeName, at: url)
            .flatMap { try? JSONDecoder().decode(EditorState.self, from: $0) }
    }

    /// Open from the sidebar (M2-2): the document is replaced in the same window, and a
    /// dirty document is never lost or silently changed.
    @MainActor static func openChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            // With "Ask to keep changes when closing documents" on, closing B would show a sheet on screen.
            check(false, "open: skipped, 'Ask to keep changes when closing documents' is on")
            return
        }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let loc = scratch.appending(path: "OpenLib")
        try? fm.createDirectory(at: loc.appending(path: "sub"), withIntermediateDirectories: true)
        let urlA = loc.appending(path: "A.md"), urlB = loc.appending(path: "B.md")
        let urlC = loc.appending(path: "sub/C.md"), urlBad = loc.appending(path: "bad.txt")
        try? "alpha".write(to: urlA, atomically: true, encoding: .utf8)
        try? "beta".write(to: urlB, atomically: true, encoding: .utf8)
        try? "gamma".write(to: urlC, atomically: true, encoding: .utf8)
        try? Data([0xFF, 0xFE, 0x41]).write(to: urlBad)
        func disk(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func canonical(_ url: URL?) -> String? { url.map(LibraryListing.canonicalPath) }
        /// Types into the window's editor inside one closed undo group, as a key event does.
        /// (Headless, no event ever ends an auto-opened group, so the document would never
        /// count as edited; ending that group by hand makes the undo manager raise later.)
        func type(_ text: String, in wc: EditorWindowController) {
            let undo = (wc.document as? NSDocument)?.undoManager
            undo?.beginUndoGrouping()
            editorTextView(wc).insertText(text, replacementRange: NSRange(location: 0, length: 0))
            undo?.endUndoGrouping()
        }
        Library.shared.addLocation(loc)

        let a = try! dc.makeDocument(withContentsOf: urlA, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(a); a.makeWindowControllers()
        let wc = a.windowControllers[0] as! EditorWindowController
        func current() -> MarkdownDocument? { wc.document as? MarkdownDocument }
        check(canonical(highlighted(wc)) == canonical(urlA) && canonical(wc.sidebar.selectedURL) == canonical(loc),
              "open: the list highlights the document the window opened with and the organizer its location")
        // As if the window had appeared (it never does headless; this shows nothing), so the
        // editor takes its swap-in-a-live-window path.
        wc.editorForTesting.viewDidAppear()
        editorTextView(wc).setSelectedRange(NSRange(location: 2, length: 0))
        // B has a caret stored from an earlier session.
        try? ExtendedAttributes.set(try! JSONEncoder().encode(EditorState(sel: [3, 0], scroll: 0)),
                                    named: EditorState.attributeName, at: urlB)

        var result: Result<Void, Error>?
        wc.replaceDocument(with: urlA) { result = $0 }
        check(wait(timeout: 3) { result != nil } && current() === a, "open: the same file is a no-op")

        result = nil
        wc.replaceDocument(with: urlB) { result = $0 }
        check(wait(timeout: 3) { result != nil } && current()?.textStorage.string == "beta",
              "open: editor shows B after opening it from the library")
        check(!dc.documents.contains(a) && current()?.windowControllers.first === wc,
              "open: A closed, same window controller now shows B")
        check(canonical(highlighted(wc)) == canonical(urlB), "open: the list highlights B")
        check(editorTextView(wc).textStorage === current()?.textStorage && current()?.editor === wc.editorForTesting,
              "open: the editor edits B's own text storage")
        check(a.editor == nil && editorState(at: urlA)?.sel == [2, 0], "open: A keeps its own caret in its xattr")
        let b = current()!
        check(editorTextView(wc).selectedRange() == NSRange(location: 3, length: 0), "open: B's stored caret is restored, not A's")
        check(!wc.editorForTesting.completion.isVisible, "open: no completion list after the swap")

        // (a) Dirty file-backed B: its edit is on disk after switching away.
        type("edit ", in: wc)
        // (Headless, isDocumentEdited never turns true; "dirty" = an undoable edit not on disk.)
        check(b.textStorage.string == "edit beta" && b.undoManager?.canUndo == true && disk(urlB) == "beta",
              "open: B has an unsaved edit after typing")
        let bCaret = editorTextView(wc).selectedRange()
        result = nil
        wc.replaceDocument(with: urlC) { result = $0 }
        check(wait(timeout: 3) { result != nil } && disk(urlB) == "edit beta",
              "open (a): switching away autosaves B's edit to disk")
        check(current()?.textStorage.string == "gamma" && wc.window?.isDocumentEdited == false,
              "open: C shows, window not marked edited")
        check(highlighted(wc)?.lastPathComponent == "C.md" && wc.fileList.folder?.name == "sub" && wc.sidebar.selectedURL.map(canonical) == canonical(loc),
              "open: the list follows the document into its subfolder, the organizer stays on the location")
        check(wait(timeout: 3) { wc.stats.model.stats?.words == 1 }, "open: stats follow the new document")
        let c = current()!
        let bState = editorState(at: urlB)
        check(bState?.sel == [bCaret.location, bCaret.length], "open: B's xattr holds B's caret")

        // (d) Undo in the new document never reaches the old one's edits.
        type("x", in: wc)
        check(wc.window?.undoManager === c.undoManager, "open: undo goes to the new document")
        var steps = 0
        while c.undoManager?.canUndo == true, steps < 20 { c.undoManager?.undo(); steps += 1 }
        check(c.textStorage.string == "gamma" && b.textStorage.string == "edit beta" && disk(urlB) == "edit beta",
              "open (d): undoing everything in C stops at C's text; B untouched")
        while c.undoManager?.canRedo == true, steps > 0 { c.undoManager?.redo(); steps -= 1 }
        check(c.textStorage.string == "xgamma", "open: redo restores C's edit")

        // (e) Typing in C never marks B edited or moves B's stored caret.
        editorTextView(wc).setSelectedRange(NSRange(location: 1, length: 0))
        check(b.textStorage.string == "edit beta" && disk(urlB) == "edit beta", "open (e): typing in C leaves B's text and file unchanged")
        // The edit started an NSDocument activity that finishes on the main run loop; a save
        // in the same run-loop turn would wait on it forever (the app always has a turn between
        // the edit and ⌘S, which is a separate event).
        _ = wait(timeout: 1) { false }
        c.save(nil)
        check(wait(timeout: 3) { disk(urlC) == "xgamma" && editorState(at: urlC)?.sel == [1, 0] },
              "open: Save writes the new document and its caret")
        check(editorState(at: urlB) == bState, "open (e): B's xattr still holds B's caret, not C's")

        // (c) Unreadable target (not UTF-8, or deleted before the read): the current document stays.
        type("y", in: wc)
        for (target, label) in [(urlBad, "not-UTF-8"), (loc.appending(path: "gone.md"), "missing")] {
            result = nil
            wc.replaceDocument(with: target) { result = $0 }
            check(wait(timeout: 3) { if case .failure = result { true } else { false } }
                  && current() === c && c.textStorage.string == "yxgamma" && dc.documents.contains(c)
                  && c.windowControllers.first === wc && c.editor === wc.editorForTesting
                  && editorTextView(wc).textStorage === c.textStorage,
                  "open (c): \(label) file leaves the current document attached, text unchanged")
        }
        check(disk(urlC) == "xgamma", "open (c): the target is read first, so the current document was not autosaved")

        // A user selection of a file row opens it; a folder row opens nothing.
        selectInList(wc, urlA)
        check(wait(timeout: 3) { current()?.fileURL?.lastPathComponent == "A.md" }, "open: selecting a file row opens it")
        check(disk(urlC) == "yxgamma", "open: C's edit was saved by the close check when A opened")
        selectInList(wc, loc.appending(path: "sub"))
        check(!wait(timeout: 0.3) { current()?.fileURL?.lastPathComponent != "A.md" }, "open: selecting a folder row opens nothing")

        // (b) Dirty untitled document: the close check asks; nothing switches until answered; Cancel keeps it.
        let u = try! HeldCloseDocument(type: "net.daringfireball.markdown")
        dc.addDocument(u); u.makeWindowControllers()
        let wc2 = u.windowControllers[0] as! EditorWindowController
        check(highlighted(wc2) == nil, "open: an untitled document highlights nothing")
        type("unsaved", in: wc2)
        result = nil
        wc2.replaceDocument(with: urlBad) { result = $0 }
        check(wait(timeout: 3) { if case .failure = result { true } else { false } } && u.answer == nil
              && wc2.document === u && u.textStorage.string == "unsaved",
              "open (c): an unreadable target never asks the current document to close (no sheet)")
        result = nil
        wc2.replaceDocument(with: urlB) { result = $0 }
        check(u.answer != nil && !wait(timeout: 0.3) { result != nil } && wc2.document === u
              && u.textStorage.string == "unsaved", "open (b): untitled dirty document asks first; no switch while unanswered")
        u.answer?(false)
        var cancelled = false
        if case .failure(let error as CocoaError) = result { cancelled = error.code == .userCancelled }
        check(cancelled && wc2.document === u && u.textStorage.string == "unsaved" && u.undoManager?.canUndo == true
              && !dc.documents.contains { $0.fileURL?.lastPathComponent == "B.md" },
              "open (b): Cancel keeps the untitled document with its text")
        u.answer = nil
        selectInList(wc2, urlB)
        check(u.answer != nil && wc2.document === u, "open (b): a list click asks the untitled document too")
        u.answer?(false)
        check(wc2.document === u && u.textStorage.string == "unsaved" && highlighted(wc2) == nil,
              "open (b): after Cancel the highlight goes back")

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "open: no window was ordered in")
        u.answer = nil
        u.updateChangeCount(.changeCleared)
        u.close()
        (wc.document as? NSDocument)?.close()
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// Behaviour from first on-screen use: a focus change never moves the list, fast switching
    /// keeps the latest click, and the same file is never opened twice.
    @MainActor static func sidebarChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else { return }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let loc = scratch.appending(path: "FixLib")
        try? fm.createDirectory(at: loc.appending(path: "a/b"), withIntermediateDirectories: true)
        let urlA = loc.appending(path: "A.md"), urlB = loc.appending(path: "B.md"), urlDeep = loc.appending(path: "a/b/deep.md")
        let urlKept = loc.appending(path: "Kept.md")
        for (url, text) in [(urlA, "alpha"), (urlB, "beta"), (urlDeep, "deep"), (urlKept, "kept")] { try? text.write(to: url, atomically: true, encoding: .utf8) }
        func canonical(_ url: URL?) -> String? { url.map(LibraryListing.canonicalPath) }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: canonical(url)!)! }
        func docs(_ url: URL) -> [NSDocument] { dc.documents.filter { canonical($0.fileURL) == canonical(url) } }
        func select(_ wc: EditorWindowController, _ url: URL) { selectInList(wc, url) }
        Library.shared.addLocation(loc)
        let dirA = loc.appending(path: "a"), dirB = loc.appending(path: "a/b")

        // Focus change: a folder the user collapsed stays collapsed.
        let deep = try! dc.makeDocument(withContentsOf: urlDeep, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(deep); deep.makeWindowControllers()
        let wcDeep = deep.windowControllers[0] as! EditorWindowController
        check(wcDeep.fileList.folder === node(dirB) && canonical(highlighted(wcDeep)) == canonical(urlDeep)
              && canonical(wcDeep.sidebar.selectedURL) == canonical(loc),
              "reveal: opening a document shows its folder in the list, selects its row and its location")
        wcDeep.fileList.showFolder(node(dirA))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: wcDeep.window)
        check(wcDeep.fileList.folder === node(dirA), "reveal: the window becoming key does not move the list")
        deep.close()

        // Fast switching: a second request while the first is pending is kept, not dropped.
        func heldWindow() -> (HeldCloseDocument, EditorWindowController) {
            let u = try! HeldCloseDocument(type: "net.daringfireball.markdown")
            dc.addDocument(u); u.makeWindowControllers()
            let wc = u.windowControllers[0] as! EditorWindowController
            return (u, wc)
        }
        func finish(_ u: HeldCloseDocument, _ wc: EditorWindowController) {
            u.answer = nil
            u.updateChangeCount(.changeCleared)
            u.close()
            (wc.document as? NSDocument)?.close()
        }
        let (u, wcFast) = heldWindow()
        select(wcFast, urlA)
        select(wcFast, urlB)
        check(u.answer != nil && canonical(highlighted(wcFast)) == canonical(urlB),
              "switch: the highlight stays on the latest click while the first switch is pending")
        u.answer?(true)
        check(wait(timeout: 3) { canonical((wcFast.document as? NSDocument)?.fileURL) == canonical(urlB) },
              "switch: the latest click (B) ends up open")
        check(canonical(highlighted(wcFast)) == canonical(urlB) && docs(urlA).isEmpty && docs(urlB).count == 1,
              "switch: B is highlighted, A is not left open")
        finish(u, wcFast)

        let (u2, wcCancel) = heldWindow()
        select(wcCancel, urlA)
        select(wcCancel, urlB)
        u2.answer?(false)
        check(wcCancel.document === u2 && docs(urlA).isEmpty && docs(urlB).isEmpty && highlighted(wcCancel) == nil,
              "switch: a cancelled switch opens nothing and the highlight goes back to the current document")
        finish(u2, wcCancel)

        // A click on the current document while a switch is pending cancels the pending target.
        let kept = try! HeldCloseDocument(contentsOf: urlKept, ofType: "net.daringfireball.markdown")
        dc.addDocument(kept); kept.makeWindowControllers()
        let wcKept = kept.windowControllers[0] as! EditorWindowController
        check(canonical(highlighted(wcKept)) == canonical(urlKept), "switch: the current document starts highlighted")
        select(wcKept, urlA)
        select(wcKept, urlKept)
        check(kept.answer != nil && canonical(highlighted(wcKept)) == canonical(urlKept),
              "switch: clicking the current document while a switch is pending keeps the highlight on it")
        kept.answer?(true)
        _ = wait(timeout: 0.5) { false }
        check(wcKept.document === kept && docs(urlA).isEmpty && canonical(highlighted(wcKept)) == canonical(urlKept),
              "switch: the pending target never opens and the current document stays highlighted")
        finish(kept, wcKept)

        // The target was opened elsewhere while the close check was held: one document, no duplicate.
        let (u3, wcDup) = heldWindow()
        var result: Result<Void, Error>?
        wcDup.replaceDocument(with: urlA) { result = $0 }
        let elsewhere = try! dc.makeDocument(withContentsOf: urlA, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(elsewhere)
        u3.answer?(true)
        var succeeded = false
        if case .success = result { succeeded = true }
        check(succeeded && docs(urlA).count == 1 && docs(urlA).first === elsewhere && wcDup.document === u3,
              "duplicate: a file opened elsewhere during the close check is not opened twice, this window keeps its document")
        elsewhere.close()
        finish(u3, wcDup)

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "sidebar: no window was ordered in")
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// Disk changes reach the file list within a second without moving its folder or losing the highlight.
    @MainActor static func liveRefreshChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            print("skip - live: NSCloseAlwaysConfirmsChanges is set, live refresh checks did not run")
            return
        }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let live = scratch.appending(path: "LiveLib")
        let L = live.appending(path: "L"), Lrenamed = live.appending(path: "L-renamed")
        try? fm.createDirectory(at: L.appending(path: "sub"), withIntermediateDirectories: true)
        for name in ["sub/x.md", "y.md"] { fm.createFile(atPath: L.appending(path: name).path, contents: Data()) }
        Library.shared.addLocation(L)
        func tree(_ path: String) -> LibraryNode { Library.shared.tree.node(atPath: LibraryListing.canonicalPath(L.appending(path: path)))! }
        let doc = try! dc.makeDocument(withContentsOf: L.appending(path: "y.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        let list = wc.fileList
        let subNode = tree("sub"), root = Library.shared.tree.roots.last!
        check(list.folder === root && highlighted(wc)?.lastPathComponent == "y.md",
              "live: setup - the location is listed, y.md highlighted")

        let before = listNames(wc).count
        fm.createFile(atPath: L.appending(path: "new.md").path, contents: Data())
        check(wait(timeout: 1) { listNames(wc).count == before + 1 }, "live: created file appears within 1 s")
        check(list.folder === root, "live: the list stays in its folder")
        check(highlighted(wc)?.lastPathComponent == "y.md", "live: active document stays highlighted")
        try! fm.moveItem(at: L.appending(path: "new.md"), to: L.appending(path: "renamed.md"))
        check(wait(timeout: 1) { listNames(wc).contains("renamed.md") && !listNames(wc).contains("new.md") }, "live: rename reflected")
        try! fm.removeItem(at: L.appending(path: "renamed.md"))
        check(wait(timeout: 1) { listNames(wc).count == before }, "live: delete reflected")

        // A folder the user descended into follows disk changes too.
        list.showFolder(subNode)
        fm.createFile(atPath: L.appending(path: "sub/hidden.md").path, contents: Data())
        check(wait(timeout: 1) { listNames(wc).contains("hidden.md") }, "live: change in a subfolder shows in the list")
        try! fm.removeItem(at: L.appending(path: "sub/hidden.md"))
        check(wait(timeout: 1) { !listNames(wc).contains("hidden.md") }, "live: and is removed again")
        list.showFolder(root)
        list.reveal(doc.fileURL)

        // A renamed loaded folder is a new node: it must appear without a crash.
        try! fm.moveItem(at: L.appending(path: "sub"), to: L.appending(path: "sub2"))
        check(wait(timeout: 1) { listNames(wc).contains("sub2") && !listNames(wc).contains("sub") }, "live: renamed folder reflected")
        check(highlighted(wc)?.lastPathComponent == "y.md", "live: highlight survives a folder rename")

        // The location itself renamed while running: bookmarks are re-resolved.
        try! fm.moveItem(at: L, to: Lrenamed)
        check(wait(timeout: 2) { locationRows(wc).contains { $0.name == Lrenamed.lastPathComponent } }, "live: renamed location re-resolved")
        check(Library.shared.tree.roots.last?.path == LibraryListing.canonicalPath(Lrenamed), "live: root tracks the new path")
        selectLocation(wc, Library.shared.tree.roots.last!)
        fm.createFile(atPath: Lrenamed.appending(path: "after.md").path, contents: Data())
        check(wait(timeout: 1) { listNames(wc).contains("after.md") }, "live: renamed location is watched at its new path")

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "live: no window was ordered in")
        doc.close()
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// Refresh edge cases: a user's folder selection survives a refresh, a root change does not
    /// swallow other changes in its batch, and a location that is deleted or recreated is not stale.
    @MainActor static func liveRefreshEdgeChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            print("skip - live edge: NSCloseAlwaysConfirmsChanges is set, live refresh edge checks did not run")
            return
        }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let edge = scratch.appending(path: "EdgeLib")
        let A = edge.appending(path: "A"), A2 = edge.appending(path: "A-renamed"), B = edge.appending(path: "B")
        let C = edge.appending(path: "C"), D = edge.appending(path: "D")
        for dir in [A.appending(path: "sub"), B, C, D] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        for url in [A.appending(path: "a.md"), A.appending(path: "sub/s.md"), B.appending(path: "b.md"),
                    C.appending(path: "c1.md"), D.appending(path: "d1.md")] { fm.createFile(atPath: url.path, contents: Data()) }
        [A, B, C, D].forEach { Library.shared.addLocation($0) }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url))! }
        func locationNames(_ wc: EditorWindowController) -> [String] { locationRows(wc).map(\.name) }
        let doc = try! dc.makeDocument(withContentsOf: A.appending(path: "a.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        check(locationNames(wc).suffix(4) == ["A", "B", "C", "D"], "edge: setup - four locations in the organizer")

        // A folder row the user selected stays selected through a refresh: no re-reveal of the document.
        let table = wc.fileList.tableView
        selectInList(wc, A.appending(path: "sub"))
        let rows = table.numberOfRows
        fm.createFile(atPath: A.appending(path: "new.md").path, contents: Data())
        check(wait(timeout: 1) { table.numberOfRows == rows + 1 }, "edge: file created beside the selected folder appears")
        check(wc.fileList.node(atRow: table.selectedRow)?.name == "sub", "edge: a refresh keeps the user's folder selection")

        // A batch with a location rename and a change in another location: both are applied.
        selectLocation(wc, node(B))
        try! fm.moveItem(at: A, to: A2)
        fm.createFile(atPath: B.appending(path: "b2.md").path, contents: Data())
        check(wait(timeout: 2) { locationNames(wc).contains("A-renamed") && listNames(wc).contains("b2.md") },
              "edge: a location rename does not swallow a change in another location")

        // The same batch handed over directly (no timing involved): the other change is applied too.
        fm.createFile(atPath: B.appending(path: "b3.md").path, contents: Data())
        Library.shared.folderChanged([
            FolderChange(path: LibraryListing.canonicalPath(A2), mustScanSubDirs: false, rootChanged: true),
            FolderChange(path: LibraryListing.canonicalPath(B), mustScanSubDirs: false, rootChanged: false),
        ])
        check(wait(timeout: 2) { listNames(wc).contains("b3.md") }, "edge: a batch holding a root change still applies its other changes")

        // A location recreated at the same path lists its new contents.
        selectLocation(wc, node(C))
        try! fm.removeItem(at: C)
        try! fm.createDirectory(at: C, withIntermediateDirectories: true)
        fm.createFile(atPath: C.appending(path: "c2.md").path, contents: Data())
        check(wait(timeout: 2) { listNames(wc).contains("c2.md") && !listNames(wc).contains("c1.md") },
              "edge: a recreated location shows its new contents")

        // A location deleted while running shows no stale children.
        selectLocation(wc, node(D))
        try! fm.removeItem(at: D)
        check(wait(timeout: 2) { !listNames(wc).contains("d1.md") }, "edge: a deleted location shows no stale files")

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "edge: no window was ordered in")
        doc.close()
        let prefix = LibraryListing.canonicalPath(edge)
        while let i = Library.shared.tree.roots.firstIndex(where: { $0.path.hasPrefix(prefix + "/") }) {
            Library.shared.removeLocation(at: i)
        }
    }

    /// What `MarkdownDocument.askAboutDiskChange` was asked during the self-check; answers are held.
    nonisolated(unsafe) static var diskAsks: [(doc: MarkdownDocument, change: MarkdownDocument.DiskChange,
                                              answer: (Bool) -> Void)] = []

    final class SaveProbe: NSObject {
        var saved: Bool?
        @objc func document(_ doc: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) { saved = didSave }
    }

    /// Another app changes, moves or deletes the file of an open document. The changes come
    /// from a separate process, as from another app; the prompt is answered through the seam.
    @MainActor static func externalChangeChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            print("skip - external: NSCloseAlwaysConfirmsChanges is set, external change checks did not run")
            return
        }
        let dir = scratch.appending(path: "External")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dc = NSDocumentController.shared
        /// Runs `command` in /bin/sh in its own process, inside the test folder.
        func elsewhere(_ command: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            p.currentDirectoryURL = dir
            try? p.run(); p.waitUntilExit()
        }
        func disk(_ name: String) -> String? { try? String(contentsOf: dir.appending(path: name), encoding: .utf8) }
        func open(_ name: String, _ text: String) -> (ErrorAnsweringDocument, EditorWindowController) {
            let url = dir.appending(path: name)
            try? text.write(to: url, atomically: false, encoding: .utf8)
            let doc = try! ErrorAnsweringDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
            // Every edit closes its own top-level undo group, as AppKit's event loop closes the
            // event's group (headless, an auto-opened event group would never close).
            doc.undoManager?.groupsByEvent = false
            dc.addDocument(doc); doc.makeWindowControllers()
            let wc = doc.windowControllers[0] as! EditorWindowController
            wc.editorForTesting.viewDidAppear()
            return (doc, wc)
        }
        /// Types inside one closed undo group (see `openChecks`), then waits a turn so a save can follow.
        func type(_ text: String, in wc: EditorWindowController) {
            let undo = (wc.document as? NSDocument)?.undoManager
            undo?.beginUndoGrouping()
            editorTextView(wc).insertText(text, replacementRange: NSRange(location: 0, length: 0))
            undo?.endUndoGrouping()
            (wc.document as? NSDocument)?.updateChangeCount(.changeDone)
            _ = wait(timeout: 0.5) { false }
        }
        /// ⌘S: the user's save, through NSDocument's own checks.
        func save(_ doc: NSDocument) -> Bool {
            let probe = SaveProbe()
            doc.save(withDelegate: probe, didSave: #selector(SaveProbe.document(_:didSave:contextInfo:)), contextInfo: nil)
            _ = wait(timeout: 3) { probe.saved != nil }
            return probe.saved == true
        }
        func asks(_ doc: MarkdownDocument) -> [MarkdownDocument.DiskChange] {
            diskAsks.filter { $0.doc === doc }.map(\.change)
        }
        func answer(_ doc: MarkdownDocument, _ followDisk: Bool) {
            diskAsks.last { $0.doc === doc }?.answer(followDisk)
        }
        func caret(_ wc: EditorWindowController) -> Int { editorTextView(wc).selectedRange().location }
        /// The user comes back to Aeris from the app that changed the file.
        func activate() { NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp) }
        diskAsks = []

        // Our own ⌘S, autosave and editor-state write never ask.
        let (own, ownWC) = open("own.md", "one")
        type("x", in: ownWC)
        let ownSaved = save(own)
        type("y", in: ownWC)
        var autosaved = false
        own.autosave(withImplicitCancellability: false) { autosaved = $0 == nil }
        _ = wait(timeout: 3) { autosaved }
        own.detachEditor()
        _ = wait(timeout: 1.5) { false }
        check(ownSaved && autosaved && disk("own.md") == "yxone" && asks(own).isEmpty && own.presented.isEmpty,
              "external: our own ⌘S, autosave and caret write never ask")
        own.close()

        // A clean document changed on disk asks and does not reload by itself.
        let (b, bWC) = open("b.md", "one")
        type("x", in: bWC)
        _ = save(b)
        editorTextView(bWC).setSelectedRange(NSRange(location: 3, length: 0))
        _ = wait(timeout: 1.5) { false }
        elsewhere("printf 'disk two' > b.md")
        let bAsked = wait(timeout: 3) { asks(b) == [.modified] }
        activate()
        check(bAsked && b.textStorage.string == "xone" && !wait(timeout: 0.5) { b.textStorage.string != "xone" },
              "external: a write to a clean document's file asks, no silent reload")
        elsewhere("printf 'disk three' > b.md; sleep 0.2; printf 'disk four' > b.md")
        check(!wait(timeout: 1.5) { asks(b).count > 1 } && b.textStorage.string == "xone",
              "external: more writes while asking collapse into the one prompt")
        answer(b, true)
        check(b.textStorage.string == "disk four" && caret(bWC) == 3 && wait(timeout: 1) { !b.hasUnautosavedChanges },
              "external: Reload shows the latest disk text, caret stays at offset 3, nothing unsaved")
        b.undoManager?.undo()
        let undone = b.textStorage.string
        b.undoManager?.undo()
        check(undone == "xone" && b.textStorage.string == "one", "external: ⌘Z after Reload restores the old text, older undo still works")
        editorTextView(bWC).setSelectedRange(NSRange(location: 2, length: 0))
        elsewhere("printf 'z' > b.md")
        check(wait(timeout: 3) { asks(b).count == 2 }, "external: a later write to the now-edited document asks again")
        answer(b, true)
        check(b.textStorage.string == "z" && caret(bWC) == 1 && b.presented.isEmpty,
              "external: Reload to shorter text clamps the caret to the new length")
        elsewhere("printf 'caf\\351' > b.md")  // Windows-1252
        check(wait(timeout: 3) { asks(b).count == 3 }, "external: a Windows-1252 write asks")
        answer(b, true)
        check(b.textStorage.string == "café" && b.encoding == .windows1252, "external: Reload detects the file's encoding again")
        b.undoManager?.undo()
        check(b.textStorage.string == "z" && b.encoding == .utf8, "external: ⌘Z after Reload restores the old encoding too")
        b.close()

        // The edited state with undo groups closed per step, as AppKit's event loop closes them:
        // Reload leaves a clean document clean, ⌘Z marks it edited.
        let (r, _) = open("r.md", "one")
        elsewhere("printf 'two' > r.md")
        check(wait(timeout: 3) { asks(r) == [.modified] }, "external: clean Reload case asks")
        let rUndo = r.undoManager!
        // The sheet's answer arrives inside the event's undo group, which closes after it.
        rUndo.beginUndoGrouping(); answer(r, true); rUndo.endUndoGrouping()
        _ = wait(timeout: 0.3) { false }
        check(r.textStorage.string == "two" && !r.isDocumentEdited, "external: after Reload a clean document is not edited")
        rUndo.undo()
        _ = wait(timeout: 0.3) { false }
        check(r.textStorage.string == "one" && r.isDocumentEdited, "external: ⌘Z after Reload marks the document edited")
        r.close()

        // A file that can't be read as text: Reload keeps the window's text and asks Ignore or
        // Close; nothing overwrites the file until Ignore.
        let (u, uWC) = open("u.md", "mine")
        type("E", in: uWC)
        elsewhere("printf 'their\\000data' > u.md")
        check(wait(timeout: 3) { asks(u) == [.modified] }, "external: unreadable case asks")
        answer(u, true)
        var uAutosaved = false
        u.autosave(withImplicitCancellability: true) { _ in uAutosaved = true }
        _ = wait(timeout: 3) { uAutosaved }
        let theirs = Data("their\0data".utf8)
        check(asks(u) == [.modified, .unreadable] && u.textStorage.string == "Emine"
              && (try? Data(contentsOf: dir.appending(path: "u.md"))) == theirs,
              "external: Reload of an unreadable file keeps the text, asks again, autosave leaves the file alone")
        check(MarkdownDocument.diskChangeAlert(for: u, .unreadable).buttons.map(\.title) == ["Ignore", "Close Without Saving"],
              "external: the unreadable question offers Ignore or Close Without Saving")
        answer(u, false)
        check(save(u) && disk("u.md") == "Emine", "external: after Ignore, a save replaces the unreadable file")
        u.close()

        // Ignore keeps the window's text; the next ⌘S writes it with no "changed by another app" error.
        let (c, cWC) = open("c.md", "mine")
        elsewhere("printf 'theirs' > c.md")
        check(wait(timeout: 3) { asks(c) == [.modified] }, "external: Ignore case asks")
        answer(c, false)
        check(!wait(timeout: 1) { asks(c).count > 1 } && c.textStorage.string == "mine" && disk("c.md") == "theirs",
              "external: Ignore keeps the window's text and leaves the file alone until saved")
        check(save(c) && disk("c.md") == "mine" && c.presented.isEmpty,
              "external: after Ignore, ⌘S writes the window's text with no error")
        // A Reload the editor refuses changes nothing, accepts nothing, and asks again.
        _ = wait(timeout: 1.5) { false }  // a write right after our own save sends no notice
        elsewhere("printf 'again' > c.md")
        check(wait(timeout: 3) { asks(c).count == 2 }, "external: refused-Reload case asks")
        editorTextView(cWC).isEditable = false
        answer(c, true)
        check(wait(timeout: 2) { asks(c).count == 3 } && c.textStorage.string == "mine",
              "external: a Reload the editor refuses keeps the text and asks again")
        editorTextView(cWC).isEditable = true
        answer(c, false)
        c.close()

        // A deleted file with unsaved edits: the text stays, autosave never re-creates the file,
        // a switch can't close it; Keep then save writes it back.
        let (d, dWC) = open("d.md", "keep me")
        type("x ", in: dWC)
        elsewhere("rm d.md")
        activate()
        check(wait(timeout: 3) { asks(d) == [.deleted] } && d.textStorage.string == "x keep me",
              "external: deleting the file of an edited document asks, text stays")
        var autosaveDone = false
        d.autosave(withImplicitCancellability: true) { _ in autosaveDone = true }
        _ = wait(timeout: 3) { autosaveDone }
        var switched: Result<Void, Error>?
        dWC.replaceDocument(with: dir.appending(path: "own.md")) { switched = $0 }
        _ = wait(timeout: 3) { switched != nil }
        check(disk("d.md") == nil && dWC.document === d && d.textStorage.string == "x keep me" && dc.documents.contains(d),
              "external: while asking, autosave doesn't re-create the file and a switch doesn't close it")
        answer(d, false)
        check(wait(timeout: 3) { disk("d.md") == "x keep me" } && d.presented.isEmpty,
              "external: Keep writes the file back")
        type("y", in: dWC)
        check(save(d) && disk("d.md") == "yx keep me" && asks(d) == [.deleted],
              "external: after Keep, ⌘S saves with no new prompt")
        d.close()

        // Close discards only once picked.
        let (e, eWC) = open("e.md", "bye")
        type("x", in: eWC)
        elsewhere("rm e.md")
        activate()
        check(wait(timeout: 3) { asks(e) == [.deleted] } && dc.documents.contains(e), "external: deleted file, Close case asks")
        check(MarkdownDocument.diskChangeAlert(for: e, .deleted).buttons.map(\.title) == ["Keep", "Close Without Saving"],
              "external: with unsaved edits the deletion question says Close Without Saving")
        answer(e, true)
        check(wait(timeout: 2) { !dc.documents.contains(e) } && disk("e.md") == nil,
              "external: Close closes the document without re-creating the file")

        // A move or rename follows the file silently.
        let (f, fWC) = open("f.md", "move")
        elsewhere("mv f.md g.md")
        check(wait(timeout: 3) { f.fileURL?.lastPathComponent == "g.md" && fWC.window?.title.hasPrefix("g") == true }
              && asks(f).isEmpty && f.textStorage.string == "move",
              "external: a rename follows the file silently and the title updates")
        f.close()

        // A coordinated delete (as Finder's or another app's) asks at once, without coming back to Aeris.
        let (k, _) = open("k.md", "coordinated")
        let kURL = dir.appending(path: "k.md")
        DispatchQueue.global().async {
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: kURL, options: .forDeleting, error: nil) {
                try? FileManager.default.removeItem(at: $0)
            }
        }
        check(wait(timeout: 3) { asks(k) == [.deleted] }, "external: a coordinated delete asks at once")
        answer(k, true)

        // A move to the Trash is a deletion; one that comes while another question is open is
        // asked once that question is answered, and Keep saves the file back in its old place.
        let previousTrash = MarkdownDocument.isInTrash
        MarkdownDocument.isInTrash = { $0.path.contains("/External/Trash/") }
        defer { MarkdownDocument.isInTrash = previousTrash }
        elsewhere("mkdir -p Trash")
        let (t, _) = open("t.md", "trash me")
        elsewhere("printf 'other' > t.md")
        check(wait(timeout: 3) { asks(t) == [.modified] }, "external: Trash case: the write asks first")
        elsewhere("mv t.md Trash/t.md")
        _ = wait(timeout: 1.5) { false }
        answer(t, false)
        check(wait(timeout: 3) { asks(t) == [.modified, .deleted] },
              "external: a move to the Trash while asking is asked after the answer")
        answer(t, false)
        check(wait(timeout: 3) { disk("t.md") == "trash me" } && t.fileURL?.path.contains("/Trash/") == false,
              "external: Keep after a move to the Trash saves the file back in its old place")
        t.close()

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "external: no window was ordered in")
    }

    /// A navigation as WebKit reports a click, without a click.
    private final class FakeNavigationAction: WKNavigationAction {
        let fakeRequest: URLRequest
        init(_ url: URL) { fakeRequest = URLRequest(url: url); super.init() }
        override var request: URLRequest { fakeRequest }
        override var navigationType: WKNavigationType { .linkActivated }
    }
    private final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

    /// File rows: name, date, excerpt and the open-document marker.
    @MainActor static func rowChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else { return }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let loc = scratch.appending(path: "RowLib")
        try? fm.createDirectory(at: loc.appending(path: "sub"), withIntermediateDirectories: true)
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -5, to: now)!
        let files: [(String, String, Date)] = [
            ("today.md", "---\ntitle: T\n---\n\n# Hello **world**\n\nSee [docs](http://x.y).", now),
            ("yday.md", "yesterday text", yesterday),
            ("old.md", "old text", older),
            ("empty.md", "", now),
            ("locked.md", "secret", now),
        ]
        let rawFiles: [(String, Data)] = [
            ("latin.md", "Caf\u{E9} cr\u{E8}me".data(using: .windowsCP1252)!),
            ("wide.md", Data([0xFF, 0xFE]) + "Wide text".data(using: .utf16LittleEndian)!),
            ("bin.md", Data([0, 1, 2, 0, 0xFF, 0x80, 0])),
        ]
        for (name, data) in rawFiles { try? data.write(to: loc.appending(path: name)) }
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: loc.appending(path: "locked.md").path) }
        for (name, text, date) in files {
            let url = loc.appending(path: name)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        try? fm.setAttributes([.posixPermissions: 0], ofItemAtPath: loc.appending(path: "locked.md").path)
        UserDefaults.standard.removeObject(forKey: FileListViewController.showExtensionsKey)
        defer { UserDefaults.standard.removeObject(forKey: FileListViewController.showExtensionsKey) }
        Library.shared.addLocation(loc)

        let doc = try! dc.makeDocument(withContentsOf: loc.appending(path: "old.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        let list = wc.fileList, table = list.tableView
        func row(_ name: String) -> Int { (0..<table.numberOfRows).first { list.node(atRow: $0)?.name == name }! }
        // An existing cell is returned as is, so a later change must reach it by itself.
        func cell(_ name: String) -> FileCellView {
            (table.view(atColumn: 0, row: row(name), makeIfNecessary: false)
                ?? table.view(atColumn: 0, row: row(name), makeIfNecessary: true)) as! FileCellView
        }
        func marked(_ name: String) -> Bool { (table.rowView(atRow: row(name), makeIfNecessary: true) as! FileRowView).showsOpenMarker }
        let short = DateFormatter(); short.dateStyle = .short; short.timeStyle = .none
        let time = DateFormatter(); time.dateStyle = .none; time.timeStyle = .short

        check(cell("today.md").nameLabel.stringValue == "today" && cell("old.md").nameLabel.stringValue == "old",
              "rows: names hide the extension by default")
        check(wait(timeout: 5) { cell("today.md").dateLabel.stringValue == time.string(from: now) && cell("yday.md").dateLabel.stringValue == "Yesterday"
              && cell("old.md").dateLabel.stringValue == short.string(from: older) },
              "rows: today shows a time, yesterday \"Yesterday\", older a short date (\(cell("today.md").dateLabel.stringValue), \(cell("yday.md").dateLabel.stringValue), \(cell("old.md").dateLabel.stringValue))")
        check(wait(timeout: 5) { cell("today.md").excerptLabel.stringValue == "Hello world See docs." }
              && wait(timeout: 5) { cell("yday.md").excerptLabel.stringValue == "yesterday text" },
              "rows: the excerpt arrives off the main thread with Markdown and front matter removed (\(cell("today.md").excerptLabel.stringValue))")
        check(wait(timeout: 5) { cell("empty.md").excerptLabel.stringValue == "No text" }, "rows: an empty file reads \"No text\"")
        check(cell("today.md").excerptLabel.maximumNumberOfLines == 2, "rows: the excerpt is at most two lines")

        // Edited on disk: the excerpt follows the new modification date.
        let todayURL = loc.appending(path: "today.md")
        // Through the real refresh path: the folder watcher's event, no manual reload.
        try? "changed".write(to: todayURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.modificationDate: older], ofItemAtPath: todayURL.path)
        check(wait(timeout: 5) { cell("today.md").excerptLabel.stringValue == "changed"
                  && cell("today.md").dateLabel.stringValue == short.string(from: older) },
              "rows: a file changed on disk shows its new date and excerpt without a reload (\(cell("today.md").dateLabel.stringValue), \(cell("today.md").excerptLabel.stringValue))")

        // Files that are not plain UTF-8 text, and one that can't be read.
        check(wait(timeout: 5) { cell("latin.md").excerptLabel.stringValue == "Caf\u{E9} cr\u{E8}me" }
              && wait(timeout: 5) { cell("wide.md").excerptLabel.stringValue == "Wide text" },
              "rows: Windows-1252 and UTF-16 files show their text (\(cell("latin.md").excerptLabel.stringValue))")
        check(wait(timeout: 5) { !cell("bin.md").dateLabel.stringValue.isEmpty } && cell("bin.md").excerptLabel.stringValue.isEmpty,
              "rows: a binary file shows no excerpt, not garbage")
        check(wait(timeout: 5) { !cell("locked.md").dateLabel.stringValue.isEmpty } && cell("locked.md").excerptLabel.stringValue.isEmpty,
              "rows: an unreadable file does not say \"No text\"")

        UserDefaults.standard.set(true, forKey: FileListViewController.showExtensionsKey)
        table.reloadData()
        check(cell("today.md").nameLabel.stringValue == "today.md", "rows: the show-extensions setting keeps the extension")

        // The marker follows the open document, not the selection.
        check(marked("old.md") && !marked("today.md") && !marked("sub"), "rows: the open document's row carries the marker")
        table.selectRowIndexes(IndexSet(integer: row("sub")), byExtendingSelection: false)
        check(marked("old.md") && !marked("sub") && (wc.document as? NSDocument)?.fileURL?.lastPathComponent == "old.md",
              "rows: selecting another row leaves the marker on the open file")
        wc.close()
    }

    /// Preview links act like links in a document: scroll, open in Aeris, or hand web/mail to
    /// the system. Nothing here opens anything outside the process.
    @MainActor static func linkChecks() {
        let dir = scratch.appending(path: "links")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let main = dir.appending(path: "Main.md"), other = dir.appending(path: "Other.md")
        let filler = (0..<60).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        try? "[Jump](#second) and [Other](Other.md)\n\n# First\n\n\(filler)\n\n## Second\n\n\(filler)\n".write(to: main, atomically: true, encoding: .utf8)
        try? "other doc".write(to: other, atomically: true, encoding: .utf8)
        let dc = NSDocumentController.shared
        let doc = try! dc.makeDocument(withContentsOf: main, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        let preview = wc.previewForTesting, web = preview.webViewForTesting
        wc.window?.setContentSize(NSSize(width: 1320, height: 400))
        wc.window?.contentView?.layoutSubtreeIfNeeded()

        var external: [URL] = [], opened: [URL] = [], errors: [Error] = []
        preview.openExternally = { external.append($0) }
        wc.presentLinkError = { errors.append($0) }
        let openLinked = preview.openDocument
        preview.openDocument = { opened.append($0) }

        func policy(_ url: URL) -> WKNavigationActionPolicy? {
            let out = Box<WKNavigationActionPolicy?>(nil)
            preview.webView(web, decidePolicyFor: FakeNavigationAction(url)) { out.value = $0 }
            return out.value
        }
        func eval(_ js: String) -> Any? {
            let out = Box<Any?>(nil), done = Box(false)
            web.evaluateJavaScript(js) { value, _ in out.value = value; done.value = true }
            _ = wait(timeout: 3) { done.value }
            return out.value
        }
        let ready = wait(timeout: 10) { (eval("!!document.getElementById('second')") as? Bool) == true }
        check(ready, "links: headings carry ids in the rendered page")
        check(ready && (eval("window.scrollY") as? Double ?? -1) == 0, "links: preview starts at the top")

        // The page's own base: relative links arrive resolved against the document's folder.
        func link(_ href: String) -> URL { LinkAction.resolve(href, documentURL: main)! }
        check(policy(link("#second")) == .cancel && external.isEmpty && opened.isEmpty,
              "links: #second is handled in the page, not sent to the system or opened")
        check(wait(timeout: 5) { (eval("window.scrollY") as? Double ?? 0) > 100 }, "links: #second scrolls the preview")
        let before = eval("window.scrollY") as? Double
        check(policy(link("#nope")) == .cancel && (eval("window.scrollY") as? Double) == before && external.isEmpty,
              "links: an unknown #anchor does nothing")
        check(policy(link("Other.md")) == .cancel && opened == [URL(fileURLWithPath: other.path)] && external.isEmpty,
              "links: Other.md asks to open the resolved file")
        let https = URL(string: "https://example.com/a")!
        check(policy(https) == .cancel && external == [https] && opened.count == 1, "links: https goes to the system")
        let mail = URL(string: "mailto:a@b.c")!
        _ = policy(mail)
        check(external == [https, mail], "links: mailto goes to the system")
        _ = policy(URL(string: "ftp://example.com/x")!)
        _ = policy(link("pic.png"))
        check(external.count == 2 && opened.count == 1, "links: other schemes and file types are ignored")

        openLinked(dir.appending(path: "Missing.md"))
        check(errors.count == 1 && (errors[0] as? CocoaError)?.code == .fileNoSuchFile && wc.document === doc,
              "links: a missing .md shows an error and leaves the document alone")
        openLinked(other)
        check(wait(timeout: 3) { (wc.document as? MarkdownDocument)?.textStorage.string == "other doc" }
              && errors.count == 1, "links: an existing .md opens in the same window")

        wc.close()
    }
}
#endif
