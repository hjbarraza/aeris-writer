#if DEBUG
import AppKit
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
        shellChecks()
        layoutChecks()
        libraryChecks()
        persistenceChecks()
        openChecks()
        sidebarChecks()
        liveRefreshChecks()
        liveRefreshEdgeChecks()
        encodingChecks()
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
        let defaultsKeys = ["NSSplitView Subview Frames \(key)"]
        func clean() { defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        EditorWindowController.layoutKey = key
        clean()
        do {
            let wc = EditorWindowController()
            let items = wc.splitViewController.splitViewItems
            check(items.count == 3 && items[0].behavior == .sidebar, "shell: sidebar | editor | preview")
            check(items[0].viewController === wc.sidebar, "shell: sidebar pane is the SidebarViewController")
            check(wc.splitViewController.splitView.autosaveName == key, "shell: layout autosave name is layoutKey")
            let toggle = MainMenu.make().item(withTitle: "View")?.submenu?.item(withTitle: "Toggle Sidebar")
            check(toggle?.action == #selector(NSSplitViewController.toggleSidebar(_:))
                  && toggle?.keyEquivalent == "s" && toggle?.keyEquivalentModifierMask == [.command, .option],
                  "shell: View > Toggle Sidebar is ⌘⌥S")
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
        let defaultsKey = "NSSplitView Subview Frames \(key)"
        let previousKey = EditorWindowController.layoutKey
        EditorWindowController.layoutKey = key
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey); EditorWindowController.layoutKey = previousKey }
        let wc = EditorWindowController()
        let split = wc.splitViewController.splitView
        func settle() { split.window?.contentView?.layoutSubtreeIfNeeded(); split.layoutSubtreeIfNeeded() }
        func widths() -> [CGFloat] { wc.splitViewController.splitViewItems.map { $0.viewController.view.frame.width } }
        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat) -> Bool { abs(a - b) <= tol }
        settle()
        // A skewed layout (one pane much narrower than the other), the case H hit.
        split.setPosition(split.subviews[0].frame.maxX + split.dividerThickness + 330, ofDividerAt: 1)
        settle()
        let start = widths()
        check(start[0] > 100 && start[1] >= 299 && start[2] >= 299 && abs(start[1] - start[2]) > 0.8 * min(start[1], start[2]),
              "layout: the split view lays out headless, skewed (\(start.map { Int($0) }))")

        wc.splitViewController.toggleSidebar(nil)
        check(wait(timeout: 2) { wc.isSidebarCollapsed }, "layout: sidebar collapsed")
        _ = wait(timeout: 0.5) { false }
        settle()
        wc.splitViewController.toggleSidebar(nil)
        check(wait(timeout: 2) { !wc.isSidebarCollapsed }, "layout: sidebar expanded")
        _ = wait(timeout: 0.5) { false }
        settle()
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
            _ = wait(timeout: 0.6) { false }
            settle()
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
        split.setPosition(300, ofDividerAt: 0)
        settle()
        check(near(widths()[0], 300, 2), "layout: the sidebar divider moves to 300 without a toggle (\(Int(widths()[0])))")
        wc.splitViewController.splitViewItems[0].isCollapsed = true
        _ = wait(timeout: 0.6) { false }
        settle()
        wc.splitViewController.toggleSidebar(nil)
        _ = wait(timeout: 0.6) { false }
        settle()
        check(!wc.isSidebarCollapsed && !near(widths()[0], after[0], 2),
              "layout: a single expand does not force the sidebar back to an older width (\(Int(after[0])) -> \(Int(widths()[0])))")
        wc.close()
    }

    /// Forgets the saved expanded folders, so a check group starts from collapsed folders
    /// instead of whatever the previous group left expanded.
    @MainActor static func resetExpandedFolders() {
        UserDefaults.standard.removeObject(forKey: "\(EditorWindowController.layoutKey).ExpandedPaths")
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
        resetExpandedFolders()
        guard let demo = demoLibrary() else {
            print("FAIL - library: docs/demo-library not found above the executable or the source file")
            exit(1)
        }
        let wc = EditorWindowController()
        wc.sidebar.loadViewIfNeeded()
        let ov = wc.sidebar.outlineView
        check(ov.numberOfRows == 0, "sidebar: empty library has no rows")
        Library.shared.addLocation(demo)
        check(ov.numberOfRows == 1, "sidebar: one row per location")
        ov.expandItem(ov.item(atRow: 0))
        check((1..<ov.numberOfRows).map { (ov.item(atRow: $0) as! LibraryNode).name } == ["Drafts", "Notes", "Welcome.md"],
              "sidebar: expanding a location lists its children")
        check(ov.isExpandable(ov.item(atRow: 1)) && !ov.isExpandable(ov.item(atRow: 3)), "sidebar: folders expand, files don't")
        Library.shared.addLocation(demo)
        check(ov.numberOfChildren(ofItem: nil) == 1, "sidebar: adding the same folder twice is a no-op")
        let add = MainMenu.make().item(withTitle: "File")?.submenu?.item(withTitle: "Add Location…")
        check(add?.action == #selector(AppDelegate.addLocation(_:)) && add?.keyEquivalent == "", "sidebar: File > Add Location… exists")
        wc.close()
    }

    @MainActor static func persistenceChecks() {
        resetExpandedFolders()
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
        let row = Library.shared.tree.roots.count - 1
        try? fm.removeItem(at: folderB)
        Library.shared.reload()
        let cell = ov.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
        check(cell?.textField?.stringValue == "PersistB (missing)" && cell?.textField?.textColor == .secondaryLabelColor,
              "persist: unresolvable location shows dimmed '(missing)'")
        check(relaunched().tree.roots.count == Library.shared.tree.roots.count, "persist: missing location kept in the store")

        let items = wc.sidebar.menuItems(forRow: row)
        check(items.map(\.title) == ["Remove from Library"] && items[0].tag == row, "menu: location row offers Remove from Library")
        ov.expandItem(ov.item(atRow: 0))
        check(wc.sidebar.menuItems(forRow: 1).isEmpty && wc.sidebar.menuItems(forRow: -1).isEmpty, "menu: child rows and empty space offer nothing")
        let before = Library.shared.tree.roots.count
        _ = items[0].target?.perform(items[0].action, with: items[0])
        check(Library.shared.tree.roots.count == before - 1 && ov.numberOfChildren(ofItem: nil) == before - 1,
              "menu: Remove from Library removes the row")

        // Saved expansion under a root that is missing right now survives; under an existing root, a gone folder is pruned.
        let expandedKey = "\(EditorWindowController.layoutKey).ExpandedPaths"
        let folderC = scratch.appending(path: "PersistC")
        try? fm.createDirectory(at: folderC, withIntermediateDirectories: true)
        Library.shared.addLocation(folderC)
        let folderD = scratch.appending(path: "PersistD")
        try? fm.createDirectory(at: folderD, withIntermediateDirectories: true)
        Library.shared.addLocation(folderD)
        let pathD = LibraryListing.canonicalPath(folderD)
        try? fm.removeItem(at: folderD)
        Library.shared.reload()
        let pathB = pathD, pathC = LibraryListing.canonicalPath(folderC)
        UserDefaults.standard.set([pathB + "/sub", pathC + "/gone"], forKey: expandedKey)
        wc.sidebar.libraryRootsDidChange()
        check(UserDefaults.standard.stringArray(forKey: expandedKey) == [pathB + "/sub"],
              "persist: expansion under a missing root is kept; a gone folder under a live root is pruned")
        resetExpandedFolders()

        // A root-changed event rebuilds the watcher on the next turn, never inside the stream's callback.
        let watcherBefore = Library.shared.watcherForTesting
        Library.shared.folderChanged([FolderChange(path: pathC, mustScanSubDirs: false, rootChanged: true)])
        check(Library.shared.watcherForTesting === watcherBefore, "watch: root-changed does not rebuild the watcher synchronously")
        check(wait(timeout: 2) { Library.shared.watcherForTesting !== watcherBefore }, "watch: root-changed rebuilds the watcher afterwards")
        wc.close()
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
        resetExpandedFolders()
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
        func row(_ ov: NSOutlineView, _ url: URL) -> IndexSet {
            IndexSet(integer: ov.row(forItem: Library.shared.tree.node(atPath: canonical(url)!)))
        }
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
        check(canonical(wc.sidebar.selectedURL) == canonical(urlA), "open: sidebar highlights the document the window opened with")
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
        check(canonical(wc.sidebar.selectedURL) == canonical(urlB), "open: sidebar highlights B")
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
        check(wc.sidebar.selectedURL?.lastPathComponent == "C.md", "open: highlight follows into a collapsed subfolder")
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
        let ov = wc.sidebar.outlineView
        ov.selectRowIndexes(row(ov, urlA), byExtendingSelection: false)
        check(wait(timeout: 3) { current()?.fileURL?.lastPathComponent == "A.md" }, "open: selecting a file row opens it")
        check(disk(urlC) == "yxgamma", "open: C's edit was saved by the close check when A opened")
        ov.selectRowIndexes(row(ov, loc.appending(path: "sub")), byExtendingSelection: false)
        check(!wait(timeout: 0.3) { current()?.fileURL?.lastPathComponent != "A.md" }, "open: selecting a folder row opens nothing")

        // (b) Dirty untitled document: the close check asks; nothing switches until answered; Cancel keeps it.
        let u = try! HeldCloseDocument(type: "net.daringfireball.markdown")
        dc.addDocument(u); u.makeWindowControllers()
        let wc2 = u.windowControllers[0] as! EditorWindowController
        check(wc2.sidebar.selectedURL == nil, "open: an untitled document highlights nothing")
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
        let ov2 = wc2.sidebar.outlineView
        ov2.expandItem(Library.shared.tree.roots.last)
        ov2.selectRowIndexes(row(ov2, urlB), byExtendingSelection: false)
        check(u.answer != nil && wc2.document === u, "open (b): a sidebar click asks the untitled document too")
        u.answer?(false)
        check(wc2.document === u && u.textStorage.string == "unsaved" && wc2.sidebar.selectedURL == nil,
              "open (b): after Cancel the highlight goes back")

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "open: no window was ordered in")
        u.answer = nil
        u.updateChangeCount(.changeCleared)
        u.close()
        (wc.document as? NSDocument)?.close()
        Library.shared.removeLocation(at: Library.shared.tree.roots.count - 1)
    }

    /// Sidebar behaviour from first on-screen use: expanded folders persist, a focus change
    /// never re-expands a collapsed folder, fast switching keeps the latest click, and the same
    /// file is never opened twice.
    @MainActor static func sidebarChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else { return }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let expandedKey = "\(EditorWindowController.layoutKey).ExpandedPaths"
        UserDefaults.standard.removeObject(forKey: expandedKey)
        defer { UserDefaults.standard.removeObject(forKey: expandedKey) }
        let loc = scratch.appending(path: "FixLib")
        try? fm.createDirectory(at: loc.appending(path: "a/b"), withIntermediateDirectories: true)
        let urlA = loc.appending(path: "A.md"), urlB = loc.appending(path: "B.md"), urlDeep = loc.appending(path: "a/b/deep.md")
        let urlKept = loc.appending(path: "Kept.md")
        for (url, text) in [(urlA, "alpha"), (urlB, "beta"), (urlDeep, "deep"), (urlKept, "kept")] { try? text.write(to: url, atomically: true, encoding: .utf8) }
        func canonical(_ url: URL?) -> String? { url.map(LibraryListing.canonicalPath) }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: canonical(url)!)! }
        func stored() -> [String] { UserDefaults.standard.stringArray(forKey: expandedKey) ?? [] }
        func docs(_ url: URL) -> [NSDocument] { dc.documents.filter { canonical($0.fileURL) == canonical(url) } }
        func select(_ ov: NSOutlineView, _ url: URL) { ov.selectRowIndexes(IndexSet(integer: ov.row(forItem: node(url))), byExtendingSelection: false) }
        Library.shared.addLocation(loc)
        let rootNode = Library.shared.tree.roots.last!
        let dirA = loc.appending(path: "a"), dirB = loc.appending(path: "a/b")

        // Expanded folders persist across windows (stand-in for launches), by canonical path.
        let first = EditorWindowController()
        first.sidebar.loadViewIfNeeded()
        let ov1 = first.sidebar.outlineView
        [rootNode, node(dirA), node(dirB)].forEach { ov1.expandItem($0) }
        first.close()
        UserDefaults.standard.set(stored() + ["/no/such/folder"], forKey: expandedKey)
        let second = EditorWindowController()
        second.sidebar.loadViewIfNeeded()
        let ov2 = second.sidebar.outlineView
        check([rootNode, node(dirA), node(dirB)].allSatisfy { ov2.isItemExpanded($0) },
              "persist: a new window has the same folders expanded")
        check(!stored().contains("/no/such/folder") && stored().contains(canonical(dirB)!),
              "persist: a path that no longer exists is dropped, the others kept")
        ov2.collapseItem(node(dirB))
        check(!stored().contains(canonical(dirB)!) && stored().contains(canonical(dirA)!),
              "persist: collapsing a folder is saved")
        second.close()

        // Focus change: a folder the user collapsed stays collapsed.
        let deep = try! dc.makeDocument(withContentsOf: urlDeep, ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(deep); deep.makeWindowControllers()
        let wcDeep = deep.windowControllers[0] as! EditorWindowController
        let ovDeep = wcDeep.sidebar.outlineView
        check(ovDeep.isItemExpanded(node(dirA)) && ovDeep.isItemExpanded(node(dirB)),
              "reveal: opening a document expands its folders")
        ovDeep.collapseItem(node(dirA))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: wcDeep.window)
        check(!ovDeep.isItemExpanded(node(dirA)), "reveal: the window becoming key does not re-expand a collapsed folder")
        deep.close()

        // Fast switching: a second request while the first is pending is kept, not dropped.
        func heldWindow() -> (HeldCloseDocument, EditorWindowController) {
            let u = try! HeldCloseDocument(type: "net.daringfireball.markdown")
            dc.addDocument(u); u.makeWindowControllers()
            let wc = u.windowControllers[0] as! EditorWindowController
            wc.sidebar.outlineView.expandItem(rootNode)
            return (u, wc)
        }
        func finish(_ u: HeldCloseDocument, _ wc: EditorWindowController) {
            u.answer = nil
            u.updateChangeCount(.changeCleared)
            u.close()
            (wc.document as? NSDocument)?.close()
        }
        let (u, wcFast) = heldWindow()
        select(wcFast.sidebar.outlineView, urlA)
        select(wcFast.sidebar.outlineView, urlB)
        check(u.answer != nil && canonical(wcFast.sidebar.selectedURL) == canonical(urlB),
              "switch: the highlight stays on the latest click while the first switch is pending")
        u.answer?(true)
        check(wait(timeout: 3) { canonical((wcFast.document as? NSDocument)?.fileURL) == canonical(urlB) },
              "switch: the latest click (B) ends up open")
        check(canonical(wcFast.sidebar.selectedURL) == canonical(urlB) && docs(urlA).isEmpty && docs(urlB).count == 1,
              "switch: B is highlighted, A is not left open")
        finish(u, wcFast)

        let (u2, wcCancel) = heldWindow()
        select(wcCancel.sidebar.outlineView, urlA)
        select(wcCancel.sidebar.outlineView, urlB)
        u2.answer?(false)
        check(wcCancel.document === u2 && docs(urlA).isEmpty && docs(urlB).isEmpty && wcCancel.sidebar.selectedURL == nil,
              "switch: a cancelled switch opens nothing and the highlight goes back to the current document")
        finish(u2, wcCancel)

        // A click on the current document while a switch is pending cancels the pending target.
        let kept = try! HeldCloseDocument(contentsOf: urlKept, ofType: "net.daringfireball.markdown")
        dc.addDocument(kept); kept.makeWindowControllers()
        let wcKept = kept.windowControllers[0] as! EditorWindowController
        wcKept.sidebar.outlineView.expandItem(rootNode)
        check(canonical(wcKept.sidebar.selectedURL) == canonical(urlKept), "switch: the current document starts highlighted")
        select(wcKept.sidebar.outlineView, urlA)
        select(wcKept.sidebar.outlineView, urlKept)
        check(kept.answer != nil && canonical(wcKept.sidebar.selectedURL) == canonical(urlKept),
              "switch: clicking the current document while a switch is pending keeps the highlight on it")
        kept.answer?(true)
        _ = wait(timeout: 0.5) { false }
        check(wcKept.document === kept && docs(urlA).isEmpty && canonical(wcKept.sidebar.selectedURL) == canonical(urlKept),
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

    /// Disk changes reach the sidebar within a second without collapsing folders or losing the highlight.
    @MainActor static func liveRefreshChecks() {
        guard !UserDefaults.standard.bool(forKey: "NSCloseAlwaysConfirmsChanges") else {
            print("skip - live: NSCloseAlwaysConfirmsChanges is set, live refresh checks did not run")
            return
        }
        let fm = FileManager.default
        let dc = NSDocumentController.shared
        let expandedKey = "\(EditorWindowController.layoutKey).ExpandedPaths"
        UserDefaults.standard.removeObject(forKey: expandedKey)
        defer { UserDefaults.standard.removeObject(forKey: expandedKey) }
        let live = scratch.appending(path: "LiveLib")
        let L = live.appending(path: "L"), Lrenamed = live.appending(path: "L-renamed")
        try? fm.createDirectory(at: L.appending(path: "sub"), withIntermediateDirectories: true)
        for name in ["sub/x.md", "y.md"] { fm.createFile(atPath: L.appending(path: name).path, contents: Data()) }
        Library.shared.addLocation(L)
        func rowNames(_ ov: NSOutlineView) -> [String] {
            (0..<ov.numberOfRows).compactMap { (ov.item(atRow: $0) as? LibraryNode)?.name }
        }
        func tree(_ path: String) -> LibraryNode { Library.shared.tree.node(atPath: LibraryListing.canonicalPath(L.appending(path: path)))! }
        let doc = try! dc.makeDocument(withContentsOf: L.appending(path: "y.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        let ov = wc.sidebar.outlineView
        let subNode = tree("sub"), root = Library.shared.tree.roots.last!
        ov.expandItem(subNode)
        check(ov.isItemExpanded(root) && ov.isItemExpanded(subNode) && wc.sidebar.selectedURL?.lastPathComponent == "y.md",
              "live: setup - location and sub expanded, y.md highlighted")

        let before = ov.numberOfRows
        fm.createFile(atPath: L.appending(path: "sub/new.md").path, contents: Data())
        check(wait(timeout: 1) { ov.numberOfRows == before + 1 }, "live: created file appears within 1 s")
        check(ov.isItemExpanded(subNode), "live: expanded folder stays expanded")
        check(wc.sidebar.selectedURL?.lastPathComponent == "y.md", "live: active document stays highlighted")
        try! fm.moveItem(at: L.appending(path: "sub/new.md"), to: L.appending(path: "sub/renamed.md"))
        check(wait(timeout: 1) { rowNames(ov).contains("renamed.md") && !rowNames(ov).contains("new.md") }, "live: rename reflected")
        try! fm.removeItem(at: L.appending(path: "sub/renamed.md"))
        check(wait(timeout: 1) { ov.numberOfRows == before }, "live: delete reflected")

        // A change under a folder that is expanded but hidden by a collapsed ancestor shows once the ancestor opens.
        ov.collapseItem(root)
        fm.createFile(atPath: L.appending(path: "sub/hidden.md").path, contents: Data())
        _ = wait(timeout: 0.6) { false }
        ov.expandItem(root)
        wc.sidebar.reveal(doc.fileURL, expandingAncestors: false)  // collapsing the location dropped the highlight; a focus change restores it
        check(rowNames(ov).contains("hidden.md") && ov.isItemExpanded(subNode), "live: change under a collapsed ancestor shows on expand")
        try! fm.removeItem(at: L.appending(path: "sub/hidden.md"))
        check(wait(timeout: 1) { !rowNames(ov).contains("hidden.md") }, "live: and is removed again")

        // A renamed loaded folder is a new node: it must appear (collapsed, or expanded if saved as expanded) without a crash.
        try! fm.moveItem(at: L.appending(path: "sub"), to: L.appending(path: "sub2"))
        check(wait(timeout: 1) { rowNames(ov).contains("sub2") && !rowNames(ov).contains("sub") }, "live: renamed folder reflected")
        check(wc.sidebar.selectedURL?.lastPathComponent == "y.md", "live: highlight survives a folder rename")

        // The location itself renamed while running: bookmarks are re-resolved.
        try! fm.moveItem(at: L, to: Lrenamed)
        check(wait(timeout: 2) { rowNames(ov).contains(Lrenamed.lastPathComponent) }, "live: renamed location re-resolved")
        check(Library.shared.tree.roots.last?.path == LibraryListing.canonicalPath(Lrenamed), "live: root tracks the new path")
        fm.createFile(atPath: Lrenamed.appending(path: "after.md").path, contents: Data())
        ov.expandItem(Library.shared.tree.roots.last!)
        check(wait(timeout: 1) { rowNames(ov).contains("after.md") }, "live: renamed location is watched at its new path")

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
        let expandedKey = "\(EditorWindowController.layoutKey).ExpandedPaths"
        UserDefaults.standard.removeObject(forKey: expandedKey)
        defer { UserDefaults.standard.removeObject(forKey: expandedKey) }
        let edge = scratch.appending(path: "EdgeLib")
        let A = edge.appending(path: "A"), A2 = edge.appending(path: "A-renamed"), B = edge.appending(path: "B")
        let C = edge.appending(path: "C"), D = edge.appending(path: "D")
        for dir in [A.appending(path: "sub"), B, C, D] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        for url in [A.appending(path: "a.md"), A.appending(path: "sub/s.md"), B.appending(path: "b.md"),
                    C.appending(path: "c1.md"), D.appending(path: "d1.md")] { fm.createFile(atPath: url.path, contents: Data()) }
        [A, B, C, D].forEach { Library.shared.addLocation($0) }
        func rowNames(_ ov: NSOutlineView) -> [String] {
            (0..<ov.numberOfRows).compactMap { (ov.item(atRow: $0) as? LibraryNode)?.name }
        }
        func node(_ url: URL) -> LibraryNode { Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url))! }
        let doc = try! dc.makeDocument(withContentsOf: A.appending(path: "a.md"), ofType: "net.daringfireball.markdown") as! MarkdownDocument
        dc.addDocument(doc); doc.makeWindowControllers()
        let wc = doc.windowControllers[0] as! EditorWindowController
        let ov = wc.sidebar.outlineView
        [B, C, D].forEach { ov.expandItem(node($0)) }
        check(rowNames(ov).contains("c1.md") && rowNames(ov).contains("d1.md") && rowNames(ov).contains("b.md"),
              "edge: setup - four locations expanded")

        // A folder row the user selected stays selected through a refresh: no re-reveal of the document.
        ov.selectRowIndexes(IndexSet(integer: ov.row(forItem: node(A.appending(path: "sub")))), byExtendingSelection: false)
        let rows = ov.numberOfRows
        fm.createFile(atPath: A.appending(path: "new.md").path, contents: Data())
        check(wait(timeout: 1) { ov.numberOfRows == rows + 1 }, "edge: file created beside the selected folder appears")
        check(wc.sidebar.selectedURL?.lastPathComponent == "sub", "edge: a refresh keeps the user's folder selection")

        // A batch with a location rename and a change in another location: both are applied.
        try! fm.moveItem(at: A, to: A2)
        fm.createFile(atPath: B.appending(path: "b2.md").path, contents: Data())
        check(wait(timeout: 2) { rowNames(ov).contains("A-renamed") && rowNames(ov).contains("b2.md") },
              "edge: a location rename does not swallow a change in another location")

        // The same batch handed over directly (no timing involved): the other change is applied too.
        fm.createFile(atPath: B.appending(path: "b3.md").path, contents: Data())
        Library.shared.folderChanged([
            FolderChange(path: LibraryListing.canonicalPath(A2), mustScanSubDirs: false, rootChanged: true),
            FolderChange(path: LibraryListing.canonicalPath(B), mustScanSubDirs: false, rootChanged: false),
        ])
        check(wait(timeout: 2) { rowNames(ov).contains("b3.md") }, "edge: a batch holding a root change still applies its other changes")

        // A location recreated at the same path lists its new contents.
        try! fm.removeItem(at: C)
        try! fm.createDirectory(at: C, withIntermediateDirectories: true)
        fm.createFile(atPath: C.appending(path: "c2.md").path, contents: Data())
        check(wait(timeout: 2) { rowNames(ov).contains("c2.md") && !rowNames(ov).contains("c1.md") },
              "edge: a recreated location shows its new contents")

        // A location deleted while running shows no stale children.
        try! fm.removeItem(at: D)
        check(wait(timeout: 2) { !rowNames(ov).contains("d1.md") }, "edge: a deleted location shows no stale files")

        check(NSApp.windows.allSatisfy { !$0.isVisible }, "edge: no window was ordered in")
        doc.close()
        let prefix = LibraryListing.canonicalPath(edge)
        while let i = Library.shared.tree.roots.firstIndex(where: { $0.path.hasPrefix(prefix + "/") }) {
            Library.shared.removeLocation(at: i)
        }
    }
}
#endif
