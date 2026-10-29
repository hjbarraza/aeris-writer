import Foundation
import Markdown

/// The rendered text of a Markdown document with all Markdown removed: for Copy as Plain Text.
/// Headings and paragraphs are text; emphasis markers go; a link is its text (the URL is
/// dropped); an image is its alt text; list items start with "• " (checkboxes "☐ "/"☑ ") or
/// "1. "; code is its text; table rows are tab-separated; raw HTML and rules are dropped.
/// Blocks are separated by a blank line, a soft line break reads as a space.
public enum PlainText {
    public static func make(_ markdown: String) -> String {
        blocks(of: MarkdownCore.parse(markdown)).joined(separator: "\n\n")
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
            case is InlineHTML: return ""
            case let image as Image: return inline(image)
            default: return inline(child)
            }
        }.joined()
    }
}
