import AppKit
import LibraryCore

/// The window for one `MarkdownDocument`. Its content is an `EditorViewController`;
/// the window controller only hands it the document.
final class EditorWindowController: NSWindowController, NSMenuItemValidation {
    private let editor = EditorViewController()
    private let preview = PreviewViewController()
    let sidebar = SidebarViewController()
    let fileList = FileListViewController()
    let splitViewController = LibrarySplitViewController()
    private var scrollSync: ScrollSync?
#if DEBUG
    var editorForTesting: EditorViewController { editor }
    var previewForTesting: PreviewViewController { preview }
#endif
    let stats: StatsController
    let statusBar: StatusBarView

    /// Defaults key prefix for the window layout (divider positions, sidebar collapse).
    /// The self-check overrides it so it never touches H's real layout.
    @MainActor static var layoutKey = "Aeris.MainSplit"

    /// The split view's autosave name. Four columns store a different layout than the earlier
    /// three, so it has its own name rather than reading a layout of the wrong shape.
    @MainActor static var splitAutosaveName: String { layoutKey + ".Columns" }

    func focusEditor() { editor.focusText() }

    var isSidebarCollapsed: Bool { splitViewController.splitViewItems[0].isCollapsed }

    init() {
        let stats = StatsController()
        let statusBar = StatusBarView(model: stats.model)
        self.stats = stats
        self.statusBar = statusBar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        let listItem = NSSplitViewItem(viewController: fileList)
        listItem.minimumThickness = 200
        listItem.maximumThickness = 420
        listItem.canCollapse = true
        let editorItem = NSSplitViewItem(viewController: editor)
        let previewItem = NSSplitViewItem(viewController: preview)
        // The sidebar and the file list hold their widths (only their dividers resize them); the
        // editor and preview take every other change equally, so they keep their ratio.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 280)
        listItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        editorItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
        previewItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
        editorItem.minimumThickness = 300
        previewItem.minimumThickness = 300
        let split = splitViewController
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(listItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        split.splitView.isVertical = true
        window.contentViewController = ContentViewController(split: split, statusBar: statusBar)
        window.setContentSize(NSSize(width: 1320, height: 760))
        // AppKit owns divider positions and sidebar collapse (restored from this autosave name).
        let hasSavedLayout = UserDefaults.standard.object(
            forKey: "NSSplitView Subview Frames \(Self.splitAutosaveName)") != nil
        split.splitView.autosaveName = Self.splitAutosaveName
        if !hasSavedLayout {
            window.contentView?.layoutSubtreeIfNeeded()
            let divider = split.splitView.dividerThickness
            split.splitView.setPosition(220, ofDividerAt: 0)
            split.splitView.setPosition(220 + divider + 260, ofDividerAt: 1)
            split.splitView.setPosition(220 + divider + 260 + divider + 420, ofDividerAt: 2)
        }
        window.center()
        window.isRestorable = !AppDefaults.isolated
        // Ctrl-Tab moves the keyboard between the editor and the sidebar.
        window.autorecalculatesKeyViewLoop = true
        // New documents and File > Open join the key window as tabs.
        window.tabbingMode = .preferred
        super.init(window: window)
        applyPreviewMode(animated: false)
        fileList.onOpenElsewhere = { [weak self] url, asTab in self?.preview.open(url, asTab: asTab) }
        NotificationCenter.default.addObserver(self, selector: #selector(splitDidResize(_:)),
                                               name: NSSplitView.didResizeSubviewsNotification, object: split.splitView)
        preview.openDocument = { [weak self] url in self?.openLinked(url) }
        editor.onLink = { [weak self] url in self?.preview.handleLink(url) }
        fileList.onOpen = { [weak self] url, focusEditor in self?.open(url, focusEditor: focusEditor) }
        sidebar.onFolderSelected = { [weak self] folder in
            guard let self else { return }
            fileList.showFolder(folder)
            fileList.reveal((document as? NSDocument)?.fileURL)
        }
        fileList.onStateChange = { [weak self] in self?.libraryViewChanged() }
        sidebar.onStateChange = { [weak self] in self?.libraryViewChanged() }
        fileList.onNavigate = { [weak self] in self?.fileList.reveal((self?.document as? NSDocument)?.fileURL) }
        presentLinkError = { [weak self] error in
            guard let window = self?.window else { return }
            window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: window)
    }

    // MARK: Tabs (M2-26)

    /// The tab bar's +: a new untitled document as a tab of this window, listing this tab's folder.
    override func newWindowForTab(_ sender: Any?) {
        let controller = NSDocumentController.shared
        guard let host = window, let type = controller.defaultType,
              let doc = try? controller.makeUntitledDocument(ofType: type) else { return }
        controller.addDocument(doc)
        doc.makeWindowControllers()
        guard let new = doc.windowControllers.first as? EditorWindowController, let newWindow = new.window else { return }
        new.fileList.showFolder(fileList.folder)
        newWindow.tabbingMode = .preferred
        host.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// The window controller that was key before the current one: a new tab takes its library widths.
    @MainActor private static weak var lastKey: EditorWindowController?
    @MainActor private static var syncingWidths = false

    /// The organizer's and the list's widths, or nil while either is collapsed.
    private var libraryWidths: [CGFloat]? {
        let items = splitViewController.splitViewItems[0..<2]
        guard items.allSatisfy({ !$0.isCollapsed }) else { return nil }
        return items.map { $0.viewController.view.frame.width.rounded() }
    }

    private func setLibraryWidths(_ widths: [CGFloat]) {
        guard libraryWidths != nil, libraryWidths != widths else { return }
        let split = splitViewController.splitView
        split.setPosition(widths[0], ofDividerAt: 0)
        split.setPosition(widths[0] + split.dividerThickness + widths[1], ofDividerAt: 1)
    }

    /// The other tabs of this window.
    private var siblingControllers: [EditorWindowController] {
        (window?.tabbedWindows ?? []).filter { $0 !== window }.compactMap { $0.windowController as? EditorWindowController }
    }

    /// A divider moved in the key tab: the other tabs follow, so the library keeps its size across tabs.
    @objc private func splitDidResize(_ notification: Notification) {
        guard !Self.syncingWidths, window?.tabGroup?.selectedWindow === window, let widths = libraryWidths else { return }
        Self.syncingWidths = true
        defer { Self.syncingWidths = false }
        siblingControllers.forEach { $0.setLibraryWidths(widths) }
    }

    // MARK: Window restoration

    private enum StateKey {
        static let folder = "Aeris.list.folder", selection = "Aeris.list.selection", expanded = "Aeris.organizer.expanded", listExpanded = "Aeris.list.expanded"
    }

    /// The folder in the file list, its selected row and the expanded organizer folders, as paths.
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        if let path = fileList.folder?.path { coder.encode(path as NSString, forKey: StateKey.folder) }
        if let path = fileList.selectedPath { coder.encode(path as NSString, forKey: StateKey.selection) }
        coder.encode(sidebar.expandedFolderPaths as NSArray, forKey: StateKey.expanded)
        coder.encode(fileList.expandedPaths as NSArray, forKey: StateKey.listExpanded)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        restoreLibraryView(
            folderPath: coder.decodeObject(of: NSString.self, forKey: StateKey.folder) as String?,
            selectedPath: coder.decodeObject(of: NSString.self, forKey: StateKey.selection) as String?,
            expandedPaths: coder.decodeObject(of: [NSArray.self, NSString.self], forKey: StateKey.expanded) as? [String] ?? [],
            listExpandedPaths: coder.decodeObject(of: [NSArray.self, NSString.self], forKey: StateKey.listExpanded) as? [String] ?? [])
    }

    /// Puts the library columns back: a folder that no longer exists falls back to its location's
    /// root, a location that no longer resolves to the first location; a missing selection is none.
    func restoreLibraryView(folderPath: String?, selectedPath: String?, expandedPaths: [String], listExpandedPaths: [String] = []) {
        guard let folderPath else { return }
        let tree = Library.shared.tree
        let target: LibraryNode?
        if let node = tree.node(atPath: folderPath), node.isDirectory {
            target = node
        } else {
            let roots = tree.roots.filter { folderPath == $0.path || folderPath.hasPrefix($0.path + "/") }
            target = roots.max(by: { $0.path.count < $1.path.count }) ?? tree.roots.first
        }
        guard let target else { return }
        fileList.showFolder(target)
        sidebar.reveal(target.url)
        // After anything above that expands rows: the saved expansion is the final word.
        sidebar.expandFolders(atPaths: expandedPaths)
        fileList.restoreExpanded(paths: listExpandedPaths)
        fileList.restoreSelection(path: selectedPath)
        saveSession()
    }

    // MARK: Last session
    // macOS's default "close windows when quitting" drops AppKit's window state on ⌘Q, so the
    // app also stores the library view and open document of the window that changed last.

    static let sessionKey = "Aeris.LastSession"

    /// NSDocument calls this when the file is renamed, moved or saved elsewhere: the stored path follows.
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        saveSession()
    }

    private func libraryViewChanged() {
        window?.invalidateRestorableState()
        saveSession()
    }

    /// Stores this window's folder, selection, expanded organizer folders and document path. A
    /// window losing its document (closing) or showing nothing yet leaves the stored session alone.
    private func saveSession() {
        guard let document = document as? NSDocument, document.fileURL != nil || fileList.folder != nil else { return }
        var session: [String: Any] = ["expanded": sidebar.expandedFolderPaths, "listExpanded": fileList.expandedPaths]
        if let path = fileList.folder?.path { session["folder"] = path }
        if let path = fileList.selectedPath { session["selection"] = path }
        if let path = document.fileURL?.path { session["document"] = path }
        AppDefaults.store.set(session, forKey: Self.sessionKey)
    }

    /// Launch with no window restored: reopens the last document (an untitled one if it is gone)
    /// with its library view. Never marks the document edited. False if nothing was stored.
    static func reopenLastSession(display: Bool) -> Bool {
        guard let session = AppDefaults.store.dictionary(forKey: sessionKey) else { return false }
        let controller = NSDocumentController.shared
        var document: NSDocument?
        if let path = session["document"] as? String, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            document = try? controller.makeDocument(withContentsOf: url, ofType: controller.typeForContents(of: url))
        }
        if document == nil, let type = controller.defaultType {
            document = try? controller.makeUntitledDocument(ofType: type)
        }
        guard let document else { return false }
        controller.addDocument(document)
        document.makeWindowControllers()
        (document.windowControllers.first as? EditorWindowController)?.restoreLibraryView(
            folderPath: session["folder"] as? String, selectedPath: session["selection"] as? String,
            expandedPaths: session["expanded"] as? [String] ?? [], listExpandedPaths: session["listExpanded"] as? [String] ?? [])
        if display { document.showWindows() }
        return true
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        reveal((document as? NSDocument)?.fileURL, expandingAncestors: false)
        if let previous = Self.lastKey, previous !== self, siblingControllers.contains(where: { $0 === previous }),
           let widths = previous.libraryWidths {
            Self.syncingWidths = true
            setLibraryWidths(widths)
            Self.syncingWidths = false
        }
        Self.lastKey = self
    }

    /// Opens a file row the user chose in the file list. A click in the list also moves
    /// the keyboard to the editor once the document is open.
    private func open(_ url: URL, focusEditor: Bool) {
        replaceDocument(with: url) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                if (error as? CocoaError)?.code != .userCancelled, let window {
                    window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                }
                // The click didn't open anything: the highlight goes back to this window's document.
                return reveal((document as? NSDocument)?.fileURL, expandingAncestors: false)
            }
            if focusEditor { editor.focusText() }
        }
    }

    /// Shows a link's failure. Replaceable so a headless check shows nothing.
    var presentLinkError: (Error) -> Void = { _ in }

    /// Opens a Markdown file linked from the document (preview click or editor ⌘-click) in a new
    /// tab of this window (a file already open is brought forward). A missing file is reported
    /// without touching the current document.
    private func openLinked(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
            return presentLinkError(error)
        }
        preview.open(url, asTab: true)
    }

    /// Highlights `url` in the file list. A document change also selects the document's location
    /// in the organizer and brings the list to the document's folder; a focus change leaves both
    /// where the user put them.
    private func reveal(_ url: URL?, expandingAncestors: Bool = true) {
        if expandingAncestors {
            sidebar.reveal(url)
            if let url, let parent = Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url))?.parent {
                fileList.showFolder(parent)
            }
        }
        fileList.reveal(url)
        libraryViewChanged()  // programmatic selection changes count too (M2-6a)
    }

    /// The latest request that arrived while a switch was pending; it opens once that switch
    /// completes (or is dropped if it is cancelled).
    private var queuedSwitch: (url: URL, completion: @MainActor (Result<Void, Error>) -> Void)?

    /// A library switch waiting for the current document's close check (the save sheet may be up):
    /// the target, already read, and who to tell.
    private var pendingSwitch: (new: NSDocument, completion: @MainActor (Result<Void, Error>) -> Void)?

    /// Opens `url` in this window in place of the current document ; reads the target before asking the current document to close.
    /// The same file does nothing; a file open in another window brings that window forward.
    /// Otherwise the target is read first: if it can't be read, the current document is never
    /// touched (no autosave, no sheet). Then the current document's close check runs (a
    /// file-backed document autosaves; a dirty untitled one shows the save sheet, whose Cancel
    /// aborts the switch and discards what was read).
    func replaceDocument(with url: URL, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        guard let old = document as? NSDocument else { return completion(.failure(CocoaError(.fileNoSuchFile))) }
        // One switch at a time: every request that arrives meanwhile (even for the current
        // document) replaces any earlier queued one (arrow keys outrun the close check) and is
        // handled when the pending switch completes.
        guard pendingSwitch == nil else {
            queuedSwitch?.completion(.success(()))
            queuedSwitch = (url, completion)
            return
        }
        if let current = old.fileURL, LibraryListing.canonicalPath(current) == LibraryListing.canonicalPath(url) {
            return completion(.success(()))
        }
        let controller = NSDocumentController.shared
        if let other = controller.document(for: url) {
            other.showWindows()
            return completion(.success(()))
        }
        let new: NSDocument
        do {
            new = try controller.makeDocument(withContentsOf: url, ofType: controller.typeForContents(of: url))
        } catch {
            return completion(.failure(error))
        }
        pendingSwitch = (new, completion)
        old.canClose(withDelegate: self, shouldClose: #selector(closeCheckDone(_:shouldClose:contextInfo:)),
                     contextInfo: nil)
    }

    @objc(document:shouldClose:contextInfo:)
    private func closeCheckDone(_ old: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard let (new, completion) = pendingSwitch else { return }
        pendingSwitch = nil
        // Cancelled (or the window changed meanwhile): the document read for the switch is
        // dropped; it was never added to the document controller.
        guard shouldClose, old === document as? NSDocument else {
            queuedSwitch?.completion(.success(()))
            queuedSwitch = nil
            return completion(.failure(CocoaError(.userCancelled)))
        }
        let controller = NSDocumentController.shared
        // The latest click was back on the current document: the pending target never opens.
        if let queued = queuedSwitch, let current = old.fileURL,
           LibraryListing.canonicalPath(current) == LibraryListing.canonicalPath(queued.url) {
            queuedSwitch = nil
            queued.completion(.success(()))
            reveal(current, expandingAncestors: false)
            return completion(.success(()))
        }
        // The file was opened elsewhere while the close check ran: use that document, keep this
        // window's (nothing is detached, so nothing can be lost).
        if let existing = new.fileURL.flatMap({ controller.document(for: $0) }) {
            existing.showWindows()
            if queuedSwitch == nil { reveal(old.fileURL, expandingAncestors: false) }
            completion(.success(()))
            return runQueuedSwitch()
        }
        (old as? MarkdownDocument)?.detachEditor()
        old.removeWindowController(self)
        old.close()
        controller.addDocument(new)
        new.addWindowController(self)
        completion(.success(()))
        runQueuedSwitch()
    }

    private func runQueuedSwitch() {
        guard let next = queuedSwitch else { return }
        queuedSwitch = nil
        replaceDocument(with: next.url, completion: next.completion)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Preview controls (M3-9)

    static let previewModeKey = "Aeris.Preview.mode"

    /// Split shows editor and preview, Full only the preview, Hidden only the editor. Kept in the
    /// app defaults, so a new window and the next launch start the way the last change left it.
    var previewMode = PreviewMode(rawValue: AppDefaults.store.string(forKey: previewModeKey) ?? "") ?? .split {
        didSet {
            AppDefaults.store.set(previewMode.rawValue, forKey: Self.previewModeKey)
            applyPreviewMode()
        }
    }

    private func applyPreviewMode(animated: Bool = true) {
        let items = splitViewController.splitViewItems
        let full = previewMode == .full, hidden = previewMode == .hidden
        if animated {
            // Same animation as the library toggle (and none under Reduce Motion).
            splitViewController.animateCollapse {
                items[2].animator().isCollapsed = full
                items[3].animator().isCollapsed = hidden
            }
        } else {
            items[2].isCollapsed = full
            items[3].isCollapsed = hidden
        }
        preview.isActive = previewMode != .hidden
    }

    @objc func togglePreview(_ sender: Any?) { previewMode = previewMode == .hidden ? .split : .hidden }
    @objc func showPreviewSplit(_ sender: Any?) { previewMode = .split }
    @objc func showPreviewFull(_ sender: Any?) { previewMode = .full }
    @objc func reloadPreview(_ sender: Any?) { preview.reload() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePreview(_:)):
            menuItem.title = previewMode == .hidden ? "Show Preview" : "Hide Preview"
            return true
        case #selector(showPreviewSplit(_:)):
            menuItem.state = previewMode == .split ? .on : .off
            return true
        case #selector(showPreviewFull(_:)):
            menuItem.state = previewMode == .full ? .on : .off
            return true
        case #selector(reloadPreview(_:)):
            return previewMode != .hidden
        default:
            return menuItem.action.map { responds(to: $0) } ?? false
        }
    }

    /// Format and View commands reach the editor even when the preview has focus
    /// (the editor is not in the preview's responder chain; this window controller is).
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        // File commands act on the list, and only while the list is on screen.
        if FileListViewController.fileActions.contains(action) { return splitViewController.splitViewItems[1].isCollapsed ? nil : fileList }
        return EditorViewController.commandActions.contains(action) ? editor : super.supplementalTarget(forAction: action, sender: sender)
    }

    override var document: AnyObject? {
        didSet {
            editor.document = document as? MarkdownDocument
            stats.attach(to: (document as? MarkdownDocument)?.textStorage)
            preview.document = document as? MarkdownDocument
            scrollSync = (editor.view as? NSScrollView).flatMap { $0.documentView as? NSTextView }
                .map { ScrollSync(textView: $0, preview: preview) }
            // A queued click already moved the highlight on; resetting it would snap it back.
            if queuedSwitch == nil { reveal((document as? NSDocument)?.fileURL) }
        }
    }
}

enum PreviewMode: String { case split, full, hidden }

/// Holding priorities alone keep the editor and preview in proportion on window resizes and
/// on collapse, but on expand AppKit takes the width of the columns that open from the editor
/// only. Expand therefore hands the editor and preview the width back in the proportion they had.
///
/// Items: 0 organizer (sidebar), 1 file list, 2 editor, 3 preview. The organizer and the list
/// together are the library.
final class LibrarySplitViewController: NSSplitViewController {
    /// Toggles still animating, and the editor's share taken before the first of them (frames
    /// mid-animation are not a share), so a quick second press can't skew the split.
    private var togglesRunning = 0
    private var share: CGFloat = 0.5
    /// The left columns' widths when a toggle chain started; restored only if presses overlapped
    /// (which can leave a column opening at its minimum).
    private var leftWidths: [CGFloat] = [0, 0]
    private var overlapped = false

    /// Runs collapse or expand changes with the window's usual split animation; instant under Reduce Motion.
    func animateCollapse(_ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { ctx.duration = 0 }
            changes()
        }, completionHandler: completion)
    }

    private var libraryShown: Bool { !splitViewItems[0].isCollapsed || !splitViewItems[1].isCollapsed }

    /// View > Hide Library (⌘⌥S): hides the organizer and the list together, or shows both.
    override func toggleSidebar(_ sender: Any?) {
        let hide = libraryShown
        toggle {
            if self.splitViewItems[0].isCollapsed != hide { super.toggleSidebar(sender) }
            self.splitViewItems[1].animator().isCollapsed = hide
        }
    }

    /// View > Hide Organizer: hides or shows only the left column.
    @objc func toggleOrganizer(_ sender: Any?) {
        toggle { super.toggleSidebar(sender) }
    }

    /// Shows the organizer and the list.
    func showLibrary() {
        toggle {
            if self.splitViewItems[0].isCollapsed { super.toggleSidebar(nil) }
            self.splitViewItems[1].animator().isCollapsed = false
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleSidebar(_:)):
            (item as? NSMenuItem)?.title = libraryShown ? "Hide Library" : "Show Library"
            return true
        case #selector(toggleOrganizer(_:)):
            (item as? NSMenuItem)?.title = splitViewItems[0].isCollapsed ? "Show Organizer" : "Hide Organizer"
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// Runs `change` (which collapses or expands left columns) animated, then gives the editor and
    /// preview their proportion back.
    private func toggle(_ change: @escaping () -> Void) {
        let left = splitViewItems[0..<2].map(\.viewController.view)
        let editor = splitViewItems[2].viewController.view, preview = splitViewItems[3].viewController.view
        let both = !splitViewItems[2].isCollapsed && !splitViewItems[3].isCollapsed
        if togglesRunning == 0, both {
            share = editor.frame.width / (editor.frame.width + preview.frame.width)
            for i in 0..<2 where !splitViewItems[i].isCollapsed { leftWidths[i] = left[i].frame.width }
        }
        togglesRunning += 1
        if togglesRunning >= 2 { overlapped = true }
        animateCollapse(change, completion: {
            MainActor.assumeIsolated {
                self.togglesRunning -= 1
                // Only the last toggle to finish acts, and only if a left column ended up open.
                guard self.togglesRunning == 0 else { return }
                let didOverlap = self.overlapped
                self.overlapped = false
                guard self.libraryShown, !self.splitViewItems[2].isCollapsed, !self.splitViewItems[3].isCollapsed else { return }
                // Only after overlapping presses: a single toggle leaves the widths to AppKit
                // (the user may have dragged them since).
                if didOverlap {
                    if !self.splitViewItems[0].isCollapsed, self.leftWidths[0] > 0 {
                        self.splitView.setPosition(self.leftWidths[0], ofDividerAt: 0)
                    }
                    if !self.splitViewItems[1].isCollapsed, self.leftWidths[1] > 0 {
                        self.splitView.setPosition(left[0].frame.maxX + self.splitView.dividerThickness + self.leftWidths[1],
                                                   ofDividerAt: 1)
                    }
                    self.splitView.layoutSubtreeIfNeeded()
                }
                let total = editor.frame.width + preview.frame.width
                self.splitView.setPosition(editor.frame.minX + (self.share * total).rounded(), ofDividerAt: 2)
            }
        })
    }
}

/// The split view with the status bar under it.
private final class ContentViewController: NSViewController {
    init(split: NSSplitViewController, statusBar: NSView) {
        super.init(nibName: nil, bundle: nil)
        addChild(split)
        let root = NSView()
        split.view.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(split.view)
        root.addSubview(statusBar)
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: root.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
