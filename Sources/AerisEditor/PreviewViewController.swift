import AppKit
import WebKit
import MarkdownCore

/// Renders the document's text storage as HTML in a WKWebView. It re-renders, debounced,
/// only when characters change, so the live styler's attribute-only edits don't trigger
/// it. Parsing and HTML generation run off the main thread on a snapshot of the text;
/// only the web view update happens on main. After the first load the body is swapped
/// in place, which keeps scroll position and avoids flashing.
final class PreviewViewController: NSViewController, WKNavigationDelegate {
    private var webView: PreviewWebView!
    private var loaded = false
    /// False from issuing a page load until it finishes. A body swap before then would
    /// hit the old or blank page and be lost when the load commits, so it waits here.
    private var pageReady = false
    private var pendingBody: String?
    private var pendingLang: String?
    /// The latest page load: an earlier one's late didFinish must not mark this page ready.
    private var pageNav: WKNavigation?
    private var observer: NSObjectProtocol?
    private var debounce: Timer?
    /// Source line the preview should show at its top (see `scroll(toSourceLine:)`).
    private var syncLine = 0.0
    /// Bumped on every character edit. A finished render is shown when its snapshot is
    /// newer than the one on screen, so the preview keeps up while typing continues.
    private var generation = 0
    private var shownGeneration = 0

    /// A new document, or its whole text replaced (revert): no render of the text
    /// before this point may show.
    private func startEpoch() {
        generation += 1
        shownGeneration = generation - 1
    }

    #if DEBUG
    var webViewForTesting: PreviewWebView { webView }
    #endif

    weak var document: MarkdownDocument? {
        didSet {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let storage = document?.textStorage else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
            ) { [weak self] note in
                // Delivered on the main queue. Attribute-only edits (live styling) are ignored.
                guard let storage = note.object as? NSTextStorage,
                      storage.editedMask.contains(.editedCharacters) else { return }
                let replacedAll = storage.editedRange == NSRange(location: 0, length: storage.length)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if replacedAll { self.startEpoch() } else { self.generation += 1 }
                    self.scheduleRender()
                }
            }
            loaded = false
            startEpoch()
            render()
        }
    }

    override func loadView() {
        // Markdown may carry raw HTML; never run its scripts. The app's own
        // evaluateJavaScript calls are unaffected by this setting.
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = PreviewWebView(frame: .zero, configuration: config)
        webView.linkMenuItems = { [weak self] in self?.menuItems(for: $0) ?? [] }
        webView.navigationDelegate = self
        view = webView
    }

    /// False while the preview is hidden: nothing renders then. Showing it renders at once
    /// if anything changed meanwhile.
    var isActive = true {
        didSet {
            if isActive, !oldValue, stale { stale = false; render() }
        }
    }
    private var stale = false

    /// View > Reload Preview: loads the page again from the document's current text.
    func reload() {
        loaded = false
        startEpoch()
        render()
    }

    private func scheduleRender() {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// At most one render in flight. A request while one runs is remembered and
    /// served, once, with the latest text when the running render finishes.
    private var rendering = false
    private var renderRequested = false

    private func render() {
        guard let document else { return }
        guard isActive else { stale = true; return }
        guard !rendering else { renderRequested = true; return }
        rendering = true
        let gen = generation
        let text = document.textStorage.string
        Task { [weak self] in
            let (body, lang) = await Task.detached(priority: .userInitiated) {
                (MarkdownCore.previewBody(text, sourceLines: true), MarkdownCore.language(of: text))
            }.value
            guard let self else { return }
            self.rendering = false
            if gen > self.shownGeneration {
                self.shownGeneration = gen
                self.show(body, lang: lang)
            }
            // Re-render only if the text moved on since this render's snapshot.
            if self.renderRequested, gen != self.generation {
                self.render()
            }
            self.renderRequested = false
        }
    }

    private func show(_ body: String, lang: String?) {
        guard let document else { return }
        if !loaded {
            loaded = true
            pageReady = false
            pendingBody = nil
            let title = document.displayName ?? "Preview"
            let base = document.fileURL?.deletingLastPathComponent()
            pageURL = base ?? URL(string: "about:blank")
            ownLoadsPending += 1
            pageNav = webView.loadHTMLString(
                MarkdownCore.htmlDocument(body: body, title: title, lang: lang), baseURL: base)
        } else if !pageReady {
            pendingBody = body
            pendingLang = lang
        } else {
            setBody(body, lang: lang)
        }
    }

    private func setBody(_ body: String, lang: String?) {
        // JSON-encode the strings so they are valid, fully escaped JS literals.
        guard let data = try? JSONEncoder().encode(body),
              let literal = String(data: data, encoding: .utf8),
              let langData = try? JSONEncoder().encode(lang ?? ""),
              let langLiteral = String(data: langData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("""
            document.body.innerHTML = \(literal);
            { const lang = \(langLiteral);
              if (lang) document.documentElement.lang = lang; else document.documentElement.removeAttribute('lang'); }
            """)
        applySync()  // queued after the swap, so it measures the new body
    }

    /// Scroll so the block at (fractional, 1-based) source `line` is at the top;
    /// 0 means the very top. Kept and re-applied after each re-render.
    func scroll(toSourceLine line: Double) {
        syncLine = line
        applySync()
    }

    /// Interpolates between the nearest `data-line` anchors around the line. Runs in
    /// the app's own content world: page scripts stay disabled, and the page can't
    /// define or override anything this relies on.
    private static let syncScript = """
        if (line <= 0) { window.scrollTo(0, 0); return; }
        const top = el => el.getBoundingClientRect().top + window.scrollY;
        let a = null, b = null;
        for (const el of document.querySelectorAll('[data-line]')) {
            const l = Number(el.dataset.line);
            if (l <= line) { if (!a || l > a.l) a = { l, el }; } else { b = { l, el }; break; }
        }
        let y = 0;
        if (a) { y = top(a.el); if (b) y += (top(b.el) - y) * (line - a.l) / (b.l - a.l); }
        else if (b) { y = top(b.el) * line / b.l; }
        window.scrollTo(0, y);
        """

    private func applySync() {
        webView.callAsyncJavaScript(Self.syncScript, arguments: ["line": syncLine],
                                    in: nil, in: .defaultClient)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === pageNav else { return }
        pageReady = true
        ownLoadsPending = 0  // a superseded load never reports; don't let its credit linger
        if let body = pendingBody {
            pendingBody = nil
            setBody(body, lang: pendingLang)  // applies the sync too
        } else {
            applySync()
        }
    }

    /// The base URL of the page on screen, and whether the load we just issued is still to
    /// be seen by the policy check. Only that one load is allowed; see `NavigationPolicy`.
    private var pageURL: URL?
    private var ownLoadsPending = 0

    // The preview never navigates on its own: it shows only the HTML we render. A link click
    // scrolls it, opens another Markdown file in Aeris, or goes to the system (web and mail
    // only); forms, meta refresh, iframes and file pages are all cancelled.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let kind: NavigationKind = switch navigationAction.navigationType {
        case .linkActivated: .linkActivated
        case .formSubmitted, .formResubmitted: .formSubmitted
        default: .other
        }
        let isMain = navigationAction.targetFrame?.isMainFrame ?? false
        let ownLoad = isMain && ownLoadsPending > 0 && kind == .other
        if ownLoad { ownLoadsPending -= 1 }
        let policy = NavigationPolicy.decide(url, isMainFrame: isMain, kind: kind, isOwnLoad: ownLoad,
                                             pageURL: pageURL, documentURL: document?.fileURL)
        switch policy {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .link(let action): perform(action); decisionHandler(.cancel)
        }
    }

    /// Opens a Markdown file the user linked to. The window controller sets this; without
    /// it the document controller opens the file.
    var openDocument: (URL) -> Void = { url in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
    /// Where web and mail links go. Replaceable so a headless check opens nothing.
    var openExternally: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func handleLink(_ url: URL) { perform(LinkAction.decide(url, documentURL: document?.fileURL)) }

    private func perform(_ action: LinkAction) {
        switch action {
        case .scroll(let anchor): scroll(toAnchor: anchor)
        case .openDocument(let target): openDocument(target)
        case .system(let target): openExternally(target)
        case .ignore: break
        }
    }

    /// Scrolls the heading with this id to the top; an unknown id does nothing.
    func scroll(toAnchor id: String) {
        webView.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView()", arguments: ["id": id],
                                    in: nil, in: .defaultClient)
    }

    // MARK: Link menu (M1-18)

    /// Where "Reveal in Finder" goes. Replaceable so a headless check opens nothing.
    var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Where "Copy Link" writes. Replaceable so a headless check leaves the real pasteboard alone.
    var pasteboard: NSPasteboard = .general

    /// The menu for a right-click on a link. Every item goes through `LinkAction.decide`, so the
    /// rules of a click (file host, same page, only Markdown files) apply to the menu too.
    func menuItems(for url: URL) -> [NSMenuItem] {
        let action = LinkAction.decide(url, documentURL: document?.fileURL)
        var items: [NSMenuItem] = []
        switch action {
        case .openDocument(let file):
            items = [
                BlockMenuItem("Open") { [weak self] in self?.perform(action) },
                BlockMenuItem("Open in New Tab") { [weak self] in self?.open(file, asTab: true) },
                BlockMenuItem("Open in New Window") { [weak self] in self?.open(file, asTab: false) },
                BlockMenuItem("Reveal in Finder") { [weak self] in self?.reveal(file) },
            ]
        case .system(let target):
            items = [BlockMenuItem(target.scheme?.lowercased() == "mailto" ? "Open in Mail" : "Open in Browser") { [weak self] in
                self?.perform(action)
            }]
        case .scroll:
            items = [BlockMenuItem("Jump to Section") { [weak self] in self?.perform(action) }]
        case .ignore:
            break
        }
        // A relative link in an unsaved document resolves to a meaningless about: URL: nothing to copy.
        if action == .ignore, url.scheme?.lowercased() == "about" { return items }
        items.append(BlockMenuItem("Copy Link") { [weak self] in
            self?.pasteboard.clearContents()
            self?.pasteboard.setString(url.absoluteString, forType: .string)
        })
        return items
    }

    /// Shows a menu action's error. Replaceable so a headless check shows no sheet.
    lazy var presentError: (Error) -> Void = { [weak self] error in
        if let window = self?.view.window {
            window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            NSApp.presentError(error)
        }
    }

    private func fail(missing url: URL) {
        presentError(CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]))
    }

    /// Files being opened by "Open in New Tab/Window" that have not finished: a second click
    /// must not open a second window for the same document.
    private var pendingOpens: Set<URL> = []

    private func reveal(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return fail(missing: file) }
        revealInFinder(file)
    }

    /// Opens `file` as a tab of this window, or in a window of its own. A document that is
    /// already open anywhere is brought forward instead of opened twice.
    func open(_ file: URL, asTab: Bool) {
        guard FileManager.default.fileExists(atPath: file.path) else { return fail(missing: file) }
        let dc = NSDocumentController.shared
        if let doc = dc.document(for: file) { doc.showWindows(); return }
        let key = file.standardizedFileURL
        guard pendingOpens.insert(key).inserted else { return }
        let host = view.window
        dc.openDocument(withContentsOf: file, display: false) { [weak self] doc, _, error in
            MainActor.assumeIsolated {
                self?.pendingOpens.remove(key)
                guard let doc else {
                    self?.presentError(error ?? CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: file.path]))
                    return
                }
                doc.makeWindowControllers()
                guard let window = doc.windowControllers.first?.window else { return }
                window.tabbingMode = asTab ? .preferred : .disallowed
                if asTab, let host { host.addTabbedWindow(window, ordered: .above) }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
