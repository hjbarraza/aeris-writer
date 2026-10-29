import Foundation
import MarkdownCore

/// Every Format menu command. A menu item carries one as its `representedObject`;
/// the editor turns it into a `TextEdit` here (all range maths is MarkdownCore's)
/// and applies it as one undoable change named `undoName`.
enum MarkdownElement {
    case inline(InlineMarker)
    case clearFormatting
    case insertDate, addHashtag
    case heading(Int)  // 0 = body text
    case quote, codeBlock, callout(String), displayMath, horizontalRule, pageBreak, tableOfContents
    case list(ListEdit.Kind)
    case insertTable
    case addRow(below: Bool), deleteRow, moveRow(down: Bool)
    case addColumn(after: Bool), deleteColumn, moveColumn(right: Bool)
    case align(MarkdownTable.Alignment), sort(ascending: Bool), transpose, reformat

    /// The edit for `text` and `selection`, or nil when the command doesn't apply
    /// (a table command outside a top-level table, a table of contents without
    /// headings). `parseFrom`: where table commands may start parsing (see TableEdit).
    func edit(text: String, selection: NSRange, parseFrom: Int = 0) -> TextEdit? {
        let caret = selection.location
        switch self {
        case .inline(let m): return InlineEdit.toggle(m, in: text, selection: selection)
        case .clearFormatting: return InlineEdit.clearStyles(in: text, selection: selection)
        case .insertDate: return InlineEdit.insertDate(Date(), in: text, selection: selection)
        case .addHashtag: return InlineEdit.addHashtag(in: text, selection: selection)
        case .heading(let level): return BlockEdit.heading(level, text: text, selection: selection)
        case .quote: return BlockEdit.quote(text: text, selection: selection)
        case .codeBlock: return BlockEdit.codeFence(text: text, selection: selection)
        case .callout(let kind): return BlockEdit.callout(kind: kind, text: text, selection: selection)
        case .displayMath: return BlockEdit.displayMath(text: text, selection: selection)
        case .horizontalRule: return BlockEdit.horizontalRule(text: text, selection: selection)
        case .pageBreak: return BlockEdit.pageBreak(text: text, selection: selection)
        case .tableOfContents:
            let toc = BlockEdit.tableOfContents(text: text)
            guard !toc.isEmpty else { return nil }
            return TextEdit(range: selection, replacement: toc,
                            selection: NSRange(location: caret + toc.utf16.count, length: 0))
        case .list(let kind): return ListEdit.toggleList(kind, text: text, selection: selection)
        case .insertTable: return TableEdit.insertTable(rows: 2, cols: 2, in: text, at: caret)
        case .addRow(let below): return TableEdit.addRow(below: below, in: text, at: caret, parseFrom: parseFrom)
        case .deleteRow: return TableEdit.deleteRow(in: text, at: caret, parseFrom: parseFrom)
        case .moveRow(let down): return TableEdit.moveRow(down: down, in: text, at: caret, parseFrom: parseFrom)
        case .addColumn(let after): return TableEdit.addColumn(after: after, in: text, at: caret, parseFrom: parseFrom)
        case .deleteColumn: return TableEdit.deleteColumn(in: text, at: caret, parseFrom: parseFrom)
        case .moveColumn(let right): return TableEdit.moveColumn(right: right, in: text, at: caret, parseFrom: parseFrom)
        case .align(let a):
            return TableEdit.setAlignment(a, in: text, at: caret, parseFrom: parseFrom)
        case .sort(let ascending):
            return TableEdit.sort(ascending: ascending, in: text, at: caret, parseFrom: parseFrom)
        case .transpose: return TableEdit.transpose(in: text, at: caret, parseFrom: parseFrom)
        case .reformat: return TableEdit.reformat(in: text, at: caret, parseFrom: parseFrom)
        }
    }

    /// Menu validation, without parsing: table commands need a table-looking line at
    /// the caret, a table of contents a line starting with `#`. The real edit is
    /// computed when the command runs and may still be nil (then nothing happens).
    /// Every other command always has an edit.
    func mayApply(text: String, selection: NSRange) -> Bool {
        switch self {
        case .addRow, .deleteRow, .moveRow, .addColumn, .deleteColumn, .moveColumn, .align, .sort, .transpose, .reformat:
            return TableEdit.looksLikeTable(text: text, at: selection.location)
        case .tableOfContents:
            let ns = text as NSString
            return ns.hasPrefix("#") || ns.range(of: "\n#").location != NSNotFound || ns.range(of: "\r#").location != NSNotFound
        default:
            return true
        }
    }

    var undoName: String {
        switch self {
        case .inline(let m):
            switch m {
            case .strong: return "Bold"
            case .emphasis: return "Italic"
            case .code: return "Code"
            case .strikethrough: return "Strikethrough"
            case .highlight: return "Highlight"
            case .link: return "Link"
            case .image: return "Image"
            case .footnote: return "Footnote"
            case .wikilink: return "Wikilink"
            case .comment: return "Comment"
            case .math: return "Inline Math"
            }
        case .clearFormatting: return "Clear Formatting"
        case .insertDate: return "Insert Date"
        case .addHashtag: return "Add Hashtag"
        case .heading(let level): return level == 0 ? "Body Text" : "Heading \(level)"
        case .quote: return "Quote"
        case .codeBlock: return "Code Block"
        case .callout: return "Callout"
        case .displayMath: return "Display Math"
        case .horizontalRule: return "Horizontal Rule"
        case .pageBreak: return "Page Break"
        case .tableOfContents: return "Table of Contents"
        case .list(let kind):
            switch kind {
            case .bullet: return "Bullet List"
            case .ordered: return "Numbered List"
            case .task: return "Task List"
            case .orderedTask: return "Numbered Task List"
            }
        case .insertTable: return "Insert Table"
        case .addRow(let below): return below ? "Add Row Below" : "Add Row Above"
        case .deleteRow: return "Delete Row"
        case .moveRow(let down): return down ? "Move Row Down" : "Move Row Up"
        case .addColumn(let after): return after ? "Add Column After" : "Add Column Before"
        case .deleteColumn: return "Delete Column"
        case .moveColumn(let right): return right ? "Move Column Right" : "Move Column Left"
        case .align: return "Align Column"
        case .sort: return "Sort Rows"
        case .transpose: return "Transpose Table"
        case .reformat: return "Reformat Table"
        }
    }
}
