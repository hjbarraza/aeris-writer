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
            return url.fragment(percentEncoded: false).map { .scroll(anchor: $0) } ?? .ignore
        case "file":
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
        return URL(string: destination, relativeTo: base)?.absoluteURL
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
