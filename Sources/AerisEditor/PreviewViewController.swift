import AppKit
import WebKit
import MarkdownCore

/// Renders the document's text storage as HTML in a WKWebView. It re-renders, debounced,
/// only when characters change, so the live styler's attribute-only edits don't trigger
/// it. Parsing and HTML generation run off the main thread on a snapshot of the text;
/// only the web view update happens on main. After the first load the body is swapped
/// in place, which keeps scroll position and avoids flashing.
final class PreviewViewController: NSViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var loaded = false
    /// False from issuing a page load until it finishes. A body swap before then would
    /// hit the old or blank page and be lost when the load commits, so it waits here.
    private var pageReady = false
    private var pendingBody: String?
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
    var webViewForTesting: WKWebView { webView }
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
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        view = webView
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
        guard !rendering else { renderRequested = true; return }
        rendering = true
        let gen = generation
        let text = document.textStorage.string
        Task { [weak self] in
            let body = await Task.detached(priority: .userInitiated) {
                MarkdownCore.html(text, sourceLines: true)
            }.value
            guard let self else { return }
            self.rendering = false
            if gen > self.shownGeneration {
                self.shownGeneration = gen
                self.show(body)
            }
            // Re-render only if the text moved on since this render's snapshot.
            if self.renderRequested, gen != self.generation {
                self.render()
            }
            self.renderRequested = false
        }
    }

    private func show(_ body: String) {
        guard let document else { return }
        if !loaded {
            loaded = true
            pageReady = false
            pendingBody = nil
            let title = document.displayName ?? "Preview"
            pageNav = webView.loadHTMLString(
                MarkdownCore.htmlDocument(body: body, title: title),
                baseURL: document.fileURL?.deletingLastPathComponent())
        } else if !pageReady {
            pendingBody = body
        } else {
            setBody(body)
        }
    }

    private func setBody(_ body: String) {
        // JSON-encode the string so it is a valid, fully escaped JS literal.
        guard let data = try? JSONEncoder().encode(body),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("document.body.innerHTML = \(literal)")
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
        if let body = pendingBody {
            pendingBody = nil
            setBody(body)  // applies the sync too
        } else {
            applySync()
        }
    }

    // The preview never navigates away from the document: a link scrolls it, opens another
    // Markdown file in Aeris, or goes to the system (web and mail only).
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url { handleLink(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    /// Opens a Markdown file the user linked to. The window controller sets this; without
    /// it the document controller opens the file.
    var openDocument: (URL) -> Void = { url in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
    /// Where web and mail links go. Replaceable so a headless check opens nothing.
    var openExternally: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func handleLink(_ url: URL) {
        switch LinkAction.decide(url, documentURL: document?.fileURL) {
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
}
