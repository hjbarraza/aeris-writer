import AppKit
import WebKit

/// The preview's web view. WebKit's own link menu items (Open Link in New Window, Download
/// Linked File, ...) can't work in a locked-down preview, so on a right-click the link under
/// the pointer is found first (a hit test in the app's own content world; page scripts stay
/// off) and the menu is then rebuilt: our items for a link, WebKit's Copy / Look Up / Services
/// for selected text, nothing that opens or downloads.
final class PreviewWebView: WKWebView {
    /// Our menu items for a link (absolute URL as the page resolves it).
    var linkMenuItems: (URL) -> [NSMenuItem] = { _ in [] }
    /// The link the menu being opened belongs to.
    private var contextLink: URL?

    /// WebKit item identifiers worth keeping when text is selected.
    private static let keptIdentifiers = ["Copy", "LookUp", "Translate", "Speak", "Search"]

    /// The absolute `href` of the link at `point` (view coordinates), if any.
    func link(at point: NSPoint, completion: @escaping (URL?) -> Void) {
        callAsyncJavaScript(
            "const a = document.elementFromPoint(x, y)?.closest('a[href]'); return a ? a.href : null;",
            arguments: ["x": point.x, "y": point.y], in: nil, in: .defaultClient
        ) { result in
            if case .success(let value) = result, let s = value as? String { completion(URL(string: s)) } else { completion(nil) }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        link(at: point) { [weak self] url in
            self?.showMenu(for: url, event: event)
        }
    }

    private func showMenu(for url: URL?, event: NSEvent) {
        contextLink = url
        super.rightMouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        reshape(menu, link: contextLink)
        contextLink = nil
    }

    /// Rewrites WebKit's menu in place. Exposed for the self-check.
    func reshape(_ menu: NSMenu, link: URL?) {
        func name(_ item: NSMenuItem) -> String {
            (item.identifier?.rawValue ?? "").replacingOccurrences(of: "WKMenuItemIdentifier", with: "")
        }
        let blocked = ["Link", "Download", "Image", "Frame", "Reload", "GoBack", "GoForward", "Inspect", "Media", "Video", "Audio"]
        let kept = menu.items.filter { item in
            let n = name(item)
            if item.isSeparatorItem { return false }
            if link != nil { return Self.keptIdentifiers.contains(where: n.contains) && !n.contains("Link") }
            return !blocked.contains(where: n.contains)
        }
        menu.removeAllItems()
        var items = link.map(linkMenuItems) ?? []
        if !items.isEmpty && !kept.isEmpty { items.append(.separator()) }
        for item in items + kept { menu.addItem(item) }
    }
}

/// A menu item that runs a closure.
final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { block() }
}
