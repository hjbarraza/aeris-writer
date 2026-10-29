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

    /// How much of a file is read for its excerpt: more than 200 characters need, front matter included.
    public static let prefixBytes = 16 * 1024

    /// The excerpt of a file's leading bytes, decoded by their own encoding (`TextEncoding`), or nil
    /// when they are not text. `truncated` says the bytes are a prefix of a longer file, so up to
    /// three bytes of a character cut at the end are dropped. Never contains U+FFFD or NUL.
    public static func make(data: Data, truncated: Bool, limit: Int = 200) -> String? {
        // Windows-1252 takes almost any bytes, so it only counts once no shorter UTF-8/16 cut decodes.
        var decoded: String?
        for drop in 0...(truncated ? 3 : 0) {
            if let (text, encoding) = TextEncoding.decode(data.dropLast(drop)), encoding != .windows1252 {
                decoded = text
                break
            }
        }
        guard let text = decoded ?? TextEncoding.decode(data)?.text else { return nil }
        return make(text.filter { $0 != "\u{FFFD}" }, limit: limit)
    }

    /// The excerpt of the file at `path`; nil when it can't be opened or isn't text.
    /// An empty file gives "". Only reads.
    public static func ofFile(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        // read returns nil at end of file, which is how an empty file reads.
        let data: Data
        do { data = try handle.read(upToCount: prefixBytes) ?? Data() } catch { return nil }
        return make(data: data, truncated: data.count == prefixBytes)
    }

    /// Drops a `---` block opened on the first line and closed by `---` or `...`; unclosed, the text is kept.
    private static func withoutFrontMatter(_ text: Substring) -> Substring {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let first = lines.first, isFence(first, "---"),
              let close = lines.indices.dropFirst().first(where: { isFence(lines[$0], "---") || isFence(lines[$0], "...") })
        else { return text }
        return Substring(lines[(close + 1)...].joined(separator: "\n"))
    }

    private static func isFence(_ line: Substring, _ fence: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == fence
    }
}
