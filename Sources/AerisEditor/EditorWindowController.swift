import AppKit
import LibraryCore

/// The window for one `MarkdownDocument`. Its content is an `EditorViewController`;
/// the window controller only hands it the document.
final class EditorWindowController: NSWindowController {
    private let editor = EditorViewController()
    private let preview = PreviewViewController()
    let sidebar = SidebarViewController()
    let splitViewController = LibrarySplitViewController()
    private var scrollSync: ScrollSync?
#if DEBUG
    var editorForTesting: EditorViewController { editor }
#endif
    let stats: StatsController
    let statusBar: StatusBarView

    /// Defaults key prefix for the window layout (divider positions, sidebar collapse).
    /// The self-check overrides it so it never touches H's real layout.
    @MainActor static var layoutKey = "Aeris.MainSplit"

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
        let editorItem = NSSplitViewItem(viewController: editor)
        let previewItem = NSSplitViewItem(viewController: preview)
        // The sidebar holds its width (only its divider resizes it); the editor and preview
        // take every other change equally, so they keep their ratio.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 280)
        editorItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
        previewItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
        editorItem.minimumThickness = 300
        previewItem.minimumThickness = 300
        let split = splitViewController
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        split.splitView.isVertical = true
        window.contentViewController = ContentViewController(split: split, statusBar: statusBar)
        window.setContentSize(NSSize(width: 1320, height: 760))
        // AppKit owns divider positions and sidebar collapse (restored from this autosave name).
        let hasSavedLayout = UserDefaults.standard.object(
            forKey: "NSSplitView Subview Frames \(Self.layoutKey)") != nil
        split.splitView.autosaveName = Self.layoutKey
        if !hasSavedLayout {
            split.splitView.setPosition(220, ofDividerAt: 0)
            split.splitView.setPosition(760, ofDividerAt: 1)
        }
        window.center()
        // Ctrl-Tab moves the keyboard between the editor and the sidebar.
        window.autorecalculatesKeyViewLoop = true
        super.init(window: window)
        sidebar.onOpen = { [weak self] url in
            self?.replaceDocument(with: url) { result in
                guard let self, case .failure(let error) = result else { return }
                if (error as? CocoaError)?.code != .userCancelled, let window = self.window {
                    window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                }
                // The click didn't open anything: the highlight goes back to this window's document.
                self.sidebar.reveal((self.document as? NSDocument)?.fileURL, expandingAncestors: false)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: window)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        sidebar.reveal((document as? NSDocument)?.fileURL, expandingAncestors: false)
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
            sidebar.reveal(current, expandingAncestors: false)
            return completion(.success(()))
        }
        // The file was opened elsewhere while the close check ran: use that document, keep this
        // window's (nothing is detached, so nothing can be lost).
        if let existing = new.fileURL.flatMap({ controller.document(for: $0) }) {
            existing.showWindows()
            if queuedSwitch == nil { sidebar.reveal(old.fileURL, expandingAncestors: false) }
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

    /// Format and View commands reach the editor even when the preview has focus
    /// (the editor is not in the preview's responder chain; this window controller is).
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        EditorViewController.commandActions.contains(action) ? editor : super.supplementalTarget(forAction: action, sender: sender)
    }

    override var document: AnyObject? {
        didSet {
            editor.document = document as? MarkdownDocument
            stats.attach(to: (document as? MarkdownDocument)?.textStorage)
            preview.document = document as? MarkdownDocument
            scrollSync = (editor.view as? NSScrollView).flatMap { $0.documentView as? NSTextView }
                .map { ScrollSync(textView: $0, preview: preview) }
            // A queued click already moved the highlight on; resetting it would snap it back.
            if queuedSwitch == nil { sidebar.reveal((document as? NSDocument)?.fileURL) }
        }
    }
}

/// Holding priorities alone keep the editor and preview in proportion on window resizes and
/// on collapse, but on expand AppKit takes the sidebar's width from the editor only. Expand
/// therefore hands the editor and preview the width back in the proportion they had.
final class LibrarySplitViewController: NSSplitViewController {
    /// Toggles still animating, and the editor's share taken before the first of them (frames
    /// mid-animation are not a share), so a quick second press can't skew the split.
    private var togglesRunning = 0
    private var share: CGFloat = 0.5
    /// The sidebar's width when a toggle chain started open; restored only if presses overlapped
    /// (which can leave it opening at its minimum).
    private var sidebarWidth: CGFloat = 0
    private var overlapped = false

    override func toggleSidebar(_ sender: Any?) {
        let sidebar = splitViewItems[0].viewController.view
        let editor = splitViewItems[1].viewController.view, preview = splitViewItems[2].viewController.view
        if togglesRunning == 0 {
            share = editor.frame.width / (editor.frame.width + preview.frame.width)
            if !splitViewItems[0].isCollapsed { sidebarWidth = sidebar.frame.width }
        }
        togglesRunning += 1
        if togglesRunning >= 2 { overlapped = true }
        NSAnimationContext.runAnimationGroup({ _ in super.toggleSidebar(sender) }, completionHandler: {
            MainActor.assumeIsolated {
                self.togglesRunning -= 1
                // Only the last toggle to finish acts, and only if the sidebar ended up open.
                guard self.togglesRunning == 0 else { return }
                let didOverlap = self.overlapped
                self.overlapped = false
                guard !self.splitViewItems[0].isCollapsed else { return }
                // Only after overlapping presses: a single toggle leaves the width to AppKit
                // (the user may have dragged it since).
                if didOverlap, self.sidebarWidth > 0 {
                    self.splitView.setPosition(self.sidebarWidth, ofDividerAt: 0)
                    self.splitView.layoutSubtreeIfNeeded()
                }
                let total = editor.frame.width + preview.frame.width
                self.splitView.setPosition(sidebar.frame.maxX + self.splitView.dividerThickness + (self.share * total).rounded(),
                                           ofDividerAt: 1)
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
