import AppKit
import WebKit

/// The preview's web view. WebKit's own link menu items (Open Link in New Window, Download
/// Linked File, ...) can't work in a locked-down preview, so every context menu (right-click
/// and Control-click alike) is rebuilt: only allow-listed WebKit items survive (Copy, Look Up,
/// ... for selected text) and, when the pointer is on a link, our items go on top. The link is
/// found with a hit test in the app's own content world; page scripts stay off.
final class PreviewWebView: WKWebView {
    /// Our menu items for a link (absolute URL as the page resolves it).
    var linkMenuItems: (URL) -> [NSMenuItem] = { _ in [] }

    /// WebKit item identifiers we keep, exact. Anything else, including items with no
    /// identifier, is dropped: the menu fails closed.
    static let keptIdentifiers: Set<String> = [
        "WKMenuItemIdentifierCopy", "WKMenuItemIdentifierLookUp", "WKMenuItemIdentifierTranslate",
        "WKMenuItemIdentifierSpeechMenu", "WKMenuItemIdentifierSearchWeb", "WKMenuItemIdentifierShareMenu",
    ]

    /// The absolute `href` of the link at `point` (view coordinates), if any.
    func link(at point: NSPoint, completion: @escaping (URL?) -> Void) {
        callAsyncJavaScript(
            "const a = document.elementFromPoint(x, y)?.closest('a[href]'); return a ? a.href : null;",
            arguments: ["x": point.x, "y": point.y], in: nil, in: .defaultClient
        ) { result in
            if case .success(let value) = result, let s = value as? String { completion(URL(string: s)) } else { completion(nil) }
        }
    }

    /// Bumped on every menu opening; a hit test answering for an older one is dropped.
    private(set) var menuGeneration = 0

    /// Right-click and Control-click both end here. The menu is filtered at once; the link under
    /// this event's own location is looked up after, and its items are added to the open menu
    /// when the answer arrives (an NSMenu updates live), if no newer menu has opened since.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        reshape(menu, link: nil)
        menuGeneration += 1
        let generation = menuGeneration
        link(at: convert(event.locationInWindow, from: nil)) { [weak self, weak menu] url in
            guard let self, let menu, let url, generation == menuGeneration else { return }
            addLinkItems(url, to: menu)
        }
    }

    /// Puts our items for `link` at the top of a menu already filtered by `reshape`.
    func addLinkItems(_ link: URL, to menu: NSMenu) {
        let items = linkMenuItems(link)
        guard !items.isEmpty else { return }
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        if menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
    }

    /// Rewrites WebKit's menu in place: only exact allow-listed identifiers survive.
    func reshape(_ menu: NSMenu, link: URL?) {
        let kept = menu.items.filter { Self.keptIdentifiers.contains($0.identifier?.rawValue ?? "") }
        menu.removeAllItems()
        for item in kept { menu.addItem(item) }
        if let link { addLinkItems(link, to: menu) }
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
