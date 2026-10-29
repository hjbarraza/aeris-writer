import Foundation
import Markdown

/// The few words a file list row shows under a document's name: the text with Markdown
/// removed, a leading front-matter block skipped, whitespace collapsed, cut at `limit` characters.
/// Headings, link text and code keep their text; URLs and HTML are dropped.
/// An empty result means the file has no text.
public enum Excerpt {
    public static func make(_ markdown: String, limit: Int = 200) -> String {
        var body = Substring(markdown)
        if body.hasPrefix("\u{FEFF}") { body = body.dropFirst() }
        var visible = VisibleText()
        visible.visit(MarkdownCore.parse(String(withoutFrontMatter(body))))
        let words = visible.text.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(limit))
    }

    /// Drops a `---` block opened on the first line and closed by `---` or `...`; unclosed, the text is kept.
    private static func withoutFrontMatter(_ text: Substring) -> Substring {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, isFence(first, "---"),
              let close = lines.indices.dropFirst().first(where: { isFence(lines[$0], "---") || isFence(lines[$0], "...") })
        else { return text }
        return Substring(lines[(close + 1)...].joined(separator: "\n"))
    }

    private static func isFence(_ line: Substring, _ fence: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == fence
    }
}
