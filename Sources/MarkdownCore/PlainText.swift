import Foundation
import Markdown

/// The rendered text of a Markdown document with all Markdown removed: for Copy as Plain Text.
/// Headings and paragraphs are text; emphasis markers go; a link is its text (the URL is
/// dropped); an image is its alt text; list items start with "• " (checkboxes "☐ "/"☑ ") or
/// "1. "; code is its text; table rows are tab-separated; raw HTML and rules are dropped.
/// Blocks are separated by a blank line, a soft line break reads as a space.
public enum PlainText {
    /// A leading front-matter block (see `Excerpt.withoutFrontMatter`) is not content and is dropped.
    /// Single-line footnote definitions (`[^id]: text`) leave the body and are appended at the end
    /// as "[1] text", their references reading "[1]".
    public static func make(_ markdown: String) -> String {
        let (body, notes) = footnotes(in: String(Excerpt.withoutFrontMatter(Substring(markdown))))
        var out = blocks(of: MarkdownCore.parse(body)).joined(separator: "\n\n")
        out = out.replacingOccurrences(of: "\u{E000}", with: "[").replacingOccurrences(of: "\u{E001}", with: "]")
        if !notes.isEmpty {
            let list = notes.enumerated().map { "[\($0 + 1)] \(PlainText.make($1.text))" }.joined(separator: "\n")
            out += out.isEmpty ? list : "\n\n" + list
        }
        return out
    }

    /// Takes the footnote definition lines (outside code fences) out of `text` and numbers them in
    /// order; references to them become placeholders that `make` turns into "[n]".
    private static func footnotes(in text: String) -> (body: String, notes: [(id: String, text: String)]) {
        guard text.contains("[^") else { return (text, []) }
        var kept: [Substring] = [], notes: [(id: String, text: String)] = []
        var fence: Character?
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: { $0 == " " })
            if let c = trimmed.first, c == "`" || c == "~", trimmed.prefix(3).allSatisfy({ $0 == c }) {
                fence = fence == nil ? c : (fence == c ? nil : fence)
            }
            if fence == nil, trimmed.hasPrefix("[^"), let close = trimmed.range(of: "]:") {
                let id = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
                if !id.isEmpty, !id.contains("]") {
                    notes.append((id, String(trimmed[close.upperBound...]).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            kept.append(line)
        }
        var body = kept.joined(separator: "\n")
        for (i, note) in notes.enumerated() {
            body = body.replacingOccurrences(of: "[^\(note.id)]", with: "\u{E000}\(i + 1)\u{E001}")
        }
        return (body, notes)
    }

    private static func blocks(of container: Markup) -> [String] {
        container.children.compactMap(block)
    }

    private static func block(_ node: Markup) -> String? {
        let out: String
        switch node {
        case let code as CodeBlock: out = code.code
        case is HTMLBlock, is ThematicBreak: return nil
        case let quote as BlockQuote: out = blocks(of: quote).joined(separator: "\n\n")
        case let list as UnorderedList: out = items(of: list) { _ in "• " }
        case let list as OrderedList: out = items(of: list) { "\(Int(list.startIndex) + $0). " }
        case let table as Table: out = rows(of: table)
        case is Paragraph, is Heading: out = inline(node)
        default: out = blocks(of: node).joined(separator: "\n\n")
        }
        let trimmed = out.hasSuffix("\n") ? String(out.dropLast()) : out
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One line per item; an item's further lines are indented under its text.
    private static func items(of list: ListItemContainer, marker: (Int) -> String) -> String {
        list.listItems.enumerated().map { index, item in
            var prefix = marker(index)
            if let box = item.checkbox { prefix += box == .checked ? "☑ " : "☐ " }
            let indent = String(repeating: " ", count: prefix.count)
            // A nested list follows its item's text on the next line; other blocks after a blank line.
            var body = ""
            for child in item.children {
                guard let text = block(child) else { continue }
                body += body.isEmpty ? text : (child is ListItemContainer ? "\n" : "\n\n") + text
            }
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.enumerated().map { i, line in
                i == 0 ? prefix + line : (line.isEmpty ? "" : indent + line)
            }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func rows(of table: Table) -> String {
        var rows = [Array(table.head.cells)]
        rows += table.body.rows.map { Array($0.cells) }
        return rows.map { $0.map(inline).joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func inline(_ node: Markup) -> String {
        node.children.map { child -> String in
            switch child {
            case let t as Text: return t.string
            case let c as InlineCode: return c.code
            case is SoftBreak: return " "
            case is LineBreak: return "\n"
            case let html as InlineHTML: return isLineBreakTag(html.rawHTML) ? "\n" : ""
            case let image as Image: return inline(image)
            default: return inline(child)
            }
        }.joined()
    }

    private static func isLineBreakTag(_ raw: String) -> Bool {
        let tag = raw.lowercased().filter { !$0.isWhitespace }
        return tag == "<br>" || tag == "<br/>"
    }
}
