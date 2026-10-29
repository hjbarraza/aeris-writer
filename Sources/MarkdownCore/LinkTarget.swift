import Markdown
import Foundation

/// GitHub-style heading slugs: lowercase, spaces become `-`, punctuation dropped,
/// `-1`, `-2` suffixes for repeats.
public struct HeadingSlugger {
    private var seen: [String: Int] = [:]

    public init() {}

    /// The slug of one heading's plain text, with no duplicate handling.
    public static func slug(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() {
            if ch == " " { out.append("-") }
            else if ch == "-" || ch == "_" || ch.isLetter || ch.isNumber { out.append(ch) }
        }
        return out
    }

    /// The id for the next heading with this text; repeats get `-1`, `-2`, ...
    public mutating func next(_ text: String) -> String {
        let base = Self.slug(text)
        guard let n = seen[base] else { seen[base] = 0; return base }
        var k = n + 1
        while seen["\(base)-\(k)"] != nil { k += 1 }
        let id = "\(base)-\(k)"
        seen[base] = k
        seen[id] = 0
        return id
    }
}

/// What a click on a link should do. Pure, so it can be tested without a window.
public enum LinkAction: Equatable, Sendable {
    /// Scroll to the heading with this id (already percent-decoded).
    case scroll(anchor: String)
    /// Open this Markdown file in Aeris.
    case openDocument(URL)
    /// Hand to the system: http, https, mailto.
    case system(URL)
    /// Do nothing.
    case ignore

    /// `url` is the link as the web view reports it (already resolved against the page's
    /// base). `documentURL` is the file being previewed, if saved.
    public static func decide(_ url: URL, documentURL: URL?) -> LinkAction {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .system(url)
        case "about":
            // Read the fragment from the text: a URL that went through URLRequest can lose it
            // on `about:` (non-hierarchical) URLs.
            let text = url.absoluteString
            guard let hash = text.firstIndex(of: "#") else { return .ignore }
            let fragment = String(text[text.index(after: hash)...])
            return .scroll(anchor: fragment.removingPercentEncoding ?? fragment)
        case "file":
            if let host = url.host(percentEncoded: false), !host.isEmpty, host.lowercased() != "localhost" { return .ignore }
            let dir = documentURL?.deletingLastPathComponent().standardizedFileURL.path
            let path = url.standardizedFileURL.path
            let samePage = path == dir || path == documentURL?.standardizedFileURL.path
            if let fragment = url.fragment(percentEncoded: false), samePage { return .scroll(anchor: fragment) }
            if ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased()) {
                return .openDocument(URL(fileURLWithPath: path))
            }
            return .ignore
        default:
            return .ignore
        }
    }

    /// Resolves a link destination as written in the Markdown source against the document.
    public static func resolve(_ destination: String, documentURL: URL?) -> URL? {
        let base = documentURL?.deletingLastPathComponent() ?? URL(string: "about:blank")
        let url = URL(string: destination, relativeTo: base)?.absoluteURL
        // No folder to resolve against: only `#anchor` in the same page makes sense.
        if documentURL == nil, !destination.hasPrefix("#"), url?.scheme?.lowercased() == "about" { return nil }
        return url
    }
}

/// How a navigation reached the policy check (a small mirror of WebKit's navigation type).
public enum NavigationKind: Equatable, Sendable {
    case linkActivated, formSubmitted, other
}

/// What the preview does with a navigation request. The preview only ever shows the HTML
/// Aeris renders for it, so everything but our own load, in-page `#anchor` moves and blank
/// subframes is cancelled.
public enum NavigationPolicy: Equatable, Sendable {
    case allow
    case cancel
    /// A link click: cancelled in the web view, handled by this action instead.
    case link(LinkAction)

    /// `isOwnLoad` is true for the one load the preview itself issued (`loadHTMLString`).
    /// `pageURL` is the URL of the page on screen, `documentURL` the saved file, if any.
    public static func decide(_ url: URL, isMainFrame: Bool, kind: NavigationKind, isOwnLoad: Bool,
                              pageURL: URL?, documentURL: URL?) -> NavigationPolicy {
        if kind == .linkActivated {
            return .link(LinkAction.decide(url, documentURL: documentURL))
        }
        // A form submission is a real navigation, even to `#x`.
        if kind == .formSubmitted { return .cancel }
        if !isMainFrame {
            return url.scheme?.lowercased() == "about" && ["blank", "srcdoc"].contains(url.path.lowercased()) ? .allow : .cancel
        }
        if isOwnLoad {
            // A lingering credit must not admit any other URL.
            return url.absoluteString == "about:blank" || samePage(url, pageURL) ? .allow : .cancel
        }
        if isFragmentOnlyMove(url, pageURL: pageURL) { return .allow }
        return .cancel
    }

    /// True when `url` is the page itself plus a fragment.
    /// Same URL ignoring any fragment; file URLs compare after resolving symlinks (/var vs /private/var).
    private static func samePage(_ url: URL, _ pageURL: URL?) -> Bool {
        guard let pageURL else { return false }
        func key(_ u: URL) -> String {
            let base = String(u.absoluteString.prefix { $0 != "#" })
            guard u.isFileURL, let b = URL(string: base) else { return base }
            return b.resolvingSymlinksInPath().path
        }
        return key(url) == key(pageURL)
    }

    private static func isFragmentOnlyMove(_ url: URL, pageURL: URL?) -> Bool {
        guard let pageURL, url.absoluteString.contains("#") else { return false }
        return url.absoluteString.prefix { $0 != "#" } == pageURL.absoluteString.prefix { $0 != "#" }
    }
}

extension MarkdownCore {
    /// The destination of the Markdown link whose source covers UTF-16 `index`, if any.
    public static func linkDestination(in text: String, at index: Int) -> String? {
        let conv = SpanCollector(text)
        func find(_ node: Markup) -> String? {
            if let r = node.range, !(conv.utf16Offset(r.lowerBound)...conv.utf16Offset(r.upperBound)).contains(index) {
                return nil
            }
            for child in node.children { if let hit = find(child) { return hit } }
            return (node as? Link)?.destination
        }
        return find(parse(text))
    }
}
