import Foundation
import Markdown

/// Thin wrapper over apple/swift-markdown. The app parses here; it does not
/// implement its own Markdown parser.
public enum MarkdownCore {
    /// Parse Markdown text into a swift-markdown document AST.
    public static func parse(_ text: String) -> Document {
        // Smart punctuation off: editor styling, stats and edits read text as typed.
        Document(parsing: text, options: .disableSmartOpts)
    }

    /// Render Markdown to HTML for the preview pane. With `sourceLines`, block
    /// elements carry `data-line="N"`: the 1-based source line where the block starts.
    public static func html(_ text: String, sourceLines: Bool = false) -> String {
        var walker = HTMLWalker()
        walker.sourceLines = sourceLines
        // Smart punctuation (curly quotes, en/em dashes, ellipsis) is preview-only.
        walker.visit(Document(parsing: text))
        return walker.html
    }

    /// Styling spans for the editor, in UTF-16 offsets of `text` (NSString/
    /// NSTextView units). Parent spans precede their children.
    public static func styleSpans(_ text: String) -> [StyleSpan] {
        var collector = SpanCollector(text)
        collector.walk(parse(text))
        return collector.spans
    }

    /// `styleSpans`, plus the document's restart points (see `restartPoints`).
    public static func styleSpansAndBlockStarts(_ text: String) -> (spans: [StyleSpan], blockStarts: [Int]) {
        let doc = parse(text)
        var collector = SpanCollector(text)
        collector.walk(doc)
        return (collector.spans, restartPoints(doc, collector, text as NSString, offset: 0))
    }

    /// Restart points: UTF-16 line starts where a parse of the text from there on
    /// gives the same block structure (code blocks, top-level tables) as the whole
    /// document's: the top-level blocks' starts and the starts of a top-level
    /// list's items (an item's content never depends on the items before it).
    /// Not any line start: a run of non-blank lines can begin inside a fence (its
    /// closing line), where a parse would read the closing fence as an opener.
    private static func restartPoints(_ doc: Document, _ conv: SpanCollector, _ ns: NSString, offset: Int) -> [Int] {
        var out: [Int] = []
        func lineStart(_ m: Markup) -> Int? {
            guard let r = m.range else { return nil }
            return ns.lineRange(for: NSRange(location: min(conv.utf16Offset(r.lowerBound), ns.length), length: 0)).location + offset
        }
        for block in doc.children {
            if let s = lineStart(block) { out.append(s) }
            if block is ListItemContainer { out += block.children.dropFirst().compactMap(lineStart) }
        }
        return out
    }

    /// Whether `point` (a line start) is a restart point of `text`, parsing from
    /// `parseFrom` (itself a restart point) through `point`'s line. Whether a line
    /// starts a top-level block or item depends only on the text up to that line.
    public static func isRestartPoint(_ text: String, _ point: Int, parseFrom: Int) -> Bool {
        let ns = text as NSString
        guard parseFrom >= 0, parseFrom <= point, point <= ns.length else { return false }
        if point == parseFrom { return true }
        let end = NSMaxRange(ns.lineRange(for: NSRange(location: point, length: 0)))
        let sub = ns.substring(with: NSRange(location: parseFrom, length: end - parseFrom))
        return restartPoints(parse(sub), SpanCollector(sub), sub as NSString, offset: parseFrom).contains(point)
    }

    /// Whether `index` (UTF-16) is inside a code block (fenced or indented, at any
    /// depth), parsing from `parseFrom` to the end of `index`'s run of non-blank
    /// lines. `parseFrom` must be a restart point at or before `index`'s line (0
    /// always is), never merely the start of the run. Whether a line is code
    /// depends only on the text up to it, so this agrees with a whole-document parse.
    public static func isInCodeBlock(_ text: String, at index: Int, parseFrom: Int = 0) -> Bool {
        let ns = text as NSString
        guard index >= 0, index <= ns.length else { return false }
        let block = BlockLines.block(ns, at: index)
        let from = min(max(parseFrom, 0), index)
        let sub = ns.substring(with: NSRange(location: from, length: NSMaxRange(block) - from))
        let conv = SpanCollector(sub)
        let target = index - from
        func walk(_ m: Markup) -> Bool {
            if m is CodeBlock, let r = conv.nsRange(m.range) {
                return r.location <= target && target < NSMaxRange(r)
            }
            return m.children.contains { walk($0) }
        }
        return walk(parse(sub))
    }

    /// Spans overlapping `range` (UTF-16). Currently parses the whole document
    /// and filters; incremental re-styling can narrow the parse later.
    public static func styleSpans(_ text: String, in range: NSRange) -> [StyleSpan] {
        styleSpans(text).filter { NSIntersectionRange($0.range, range).length > 0 }
    }
}

public enum StyleKind: Equatable, Sendable, CustomStringConvertible {
    case heading(level: Int)
    case strong, emphasis, strikethrough, inlineCode, link, image
    case codeBlock, blockQuote, listMarker, thematicBreak
    /// Markdown punctuation itself (`#`, `**`, backticks, `[`, `](url)`, `>`).
    case syntax

    public var description: String {
        switch self {
        case .heading(let level): return "heading\(level)"
        case .strong: return "strong"
        case .emphasis: return "emphasis"
        case .strikethrough: return "strikethrough"
        case .inlineCode: return "inlineCode"
        case .link: return "link"
        case .image: return "image"
        case .codeBlock: return "codeBlock"
        case .blockQuote: return "blockQuote"
        case .listMarker: return "listMarker"
        case .thematicBreak: return "thematicBreak"
        case .syntax: return "syntax"
        }
    }
}

public struct StyleSpan: Equatable, Sendable, CustomStringConvertible {
    /// UTF-16 range in the source string.
    public let range: NSRange
    public let kind: StyleKind

    public init(range: NSRange, kind: StyleKind) {
        self.range = range
        self.kind = kind
    }

    /// `kind@start+length`, the format the span tests use.
    public var description: String { "\(kind)@\(range.location)+\(range.length)" }
}

/// Walks the AST and turns swift-markdown source ranges (1-based line,
/// 1-based UTF-8 byte column, exclusive end) into UTF-16 spans. Syntax spans
/// come only from AST positions: a node's range minus its children's range.
/// Internal (not private) so TableEdit can reuse `utf16Offset(_:)`.
struct SpanCollector {
    var spans: [StyleSpan] = []
    private let bytes: [UInt8]
    /// UTF-8 offset of the start of each line (cmark line endings: LF, CRLF, CR).
    private var lineStarts: [Int] = [0]
    /// UTF-16 offset for each UTF-8 offset (count + 1 entries).
    private var utf16At: [Int] = []

    init(_ text: String) {
        bytes = Array(text.utf8)
        for (i, b) in bytes.enumerated() {
            if b == 0x0A || (b == 0x0D && (i + 1 == bytes.count || bytes[i + 1] != 0x0A)) {
                lineStarts.append(i + 1)
            }
        }
        utf16At.reserveCapacity(bytes.count + 1)
        var u16 = 0
        for scalar in text.unicodeScalars {
            let width = UTF8.width(scalar)
            for _ in 0..<width { utf16At.append(u16) }
            u16 += UTF16.width(scalar)
        }
        utf16At.append(u16)
    }

    /// UTF-16 offset of a swift-markdown source location.
    func utf16Offset(_ loc: SourceLocation) -> Int { utf16At[byteOffset(loc)] }

    /// Clamped to the text: swift-markdown can report column 0 (e.g. an inline
    /// code span in a lazy table row), which would otherwise be offset -1.
    private func byteOffset(_ loc: SourceLocation) -> Int {
        let line = min(max(loc.line, 1), lineStarts.count)
        return min(max(lineStarts[line - 1] + loc.column - 1, 0), bytes.count)
    }

    private mutating func emit(_ kind: StyleKind, bytes lo: Int, _ hi: Int) {
        guard hi > lo else { return }
        let start = utf16At[lo]
        spans.append(StyleSpan(range: NSRange(location: start, length: utf16At[hi] - start), kind: kind))
    }

    /// Emit `kind` over the node, plus `syntax` over the parts of the node not
    /// covered by its children (all of it when it has none).
    private mutating func emitWithMarkers(_ kind: StyleKind, _ node: Markup, _ lo: Int, _ hi: Int) {
        emit(kind, bytes: lo, hi)
        let kids = node.children.compactMap { $0.range }
        guard let first = kids.first, let last = kids.last else { emit(.syntax, bytes: lo, hi); return }
        emit(.syntax, bytes: lo, byteOffset(first.lowerBound))
        emit(.syntax, bytes: byteOffset(last.upperBound), hi)
    }

    mutating func walk(_ node: Markup) {
        if let r = node.range {
            let lo = byteOffset(r.lowerBound), hi = byteOffset(r.upperBound)
            switch node {
            case let h as Heading: emitWithMarkers(.heading(level: h.level), node, lo, hi)
            case is Strong: emitWithMarkers(.strong, node, lo, hi)
            case is Emphasis: emitWithMarkers(.emphasis, node, lo, hi)
            case is Strikethrough: emitWithMarkers(.strikethrough, node, lo, hi)
            case is Link: emitWithMarkers(.link, node, lo, hi)
            case is Image: emitWithMarkers(.image, node, lo, hi)
            case is InlineCode:
                // The range includes the backtick fences; their length is the
                // run of backticks at the range start.
                emit(.inlineCode, bytes: lo, hi)
                var n = 0
                while lo + n < hi, bytes[lo + n] == UInt8(ascii: "`") { n += 1 }
                emit(.syntax, bytes: lo, lo + n)
                emit(.syntax, bytes: max(hi - n, lo + n), hi)
            case is CodeBlock: emit(.codeBlock, bytes: lo, hi)
            case is ThematicBreak: emit(.thematicBreak, bytes: lo, hi)
            case is ListItem:
                // Marker = item start up to its first child ("- ", "1. ", "- [ ] ").
                let end = node.children.compactMap { $0.range }.first.map { byteOffset($0.lowerBound) } ?? hi
                emit(.listMarker, bytes: lo, end)
            case is BlockQuote:
                emit(.blockQuote, bytes: lo, hi)
                // A `>` sits at the quote's start column on each line that has
                // one (lazy continuation lines don't).
                for line in r.lowerBound.line...r.upperBound.line {
                    let at = byteOffset(SourceLocation(line: line, column: r.lowerBound.column, source: nil))
                    let onLine = line == lineStarts.count || at < lineStarts[line]
                    if onLine, at < hi, bytes[at] == UInt8(ascii: ">") { emit(.syntax, bytes: at, at + 1) }
                }
            default: break
            }
        }
        for child in node.children { walk(child) }
    }
}

/// AST→HTML walker covering CommonMark plus the GFM pieces we render
/// (strikethrough, tables, task lists).
private struct HTMLWalker: MarkupWalker {
    var html = ""
    var sourceLines = false
    // Table state: alignments of the table being walked, current column, and
    // whether we're inside the header row (cells render as <th>).
    private var alignments: [Table.ColumnAlignment?] = []
    private var column = 0
    private var inHead = false
    // One entry per list being walked: true if tight (no <p> in direct items).
    private var tightLists: [Bool] = []
    private var slugger = HeadingSlugger()

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.parent is ListItem, tightLists.last == true {
            descendInto(paragraph)
            // Separate from a following sibling block (e.g. a nested list).
            if let item = paragraph.parent, paragraph.indexInParent < item.childCount - 1 { html += "\n" }
            return
        }
        html += "<p\(line(paragraph))>"; descendInto(paragraph); html += "</p>\n"
    }
    mutating func visitHeading(_ heading: Heading) {
        let l = heading.level
        let id = slugger.next(heading.plainText)
        let idAttr = id.isEmpty ? "" : " id=\"\(escape(id, attribute: true))\""
        html += "<h\(l)\(idAttr)\(line(heading))>"; descendInto(heading); html += "</h\(l)>\n"
    }
    mutating func visitText(_ text: Text) { html += escape(text.string) }
    mutating func visitEmphasis(_ emphasis: Emphasis) {
        html += "<em>"; descendInto(emphasis); html += "</em>"
    }
    mutating func visitStrong(_ strong: Strong) {
        html += "<strong>"; descendInto(strong); html += "</strong>"
    }
    mutating func visitInlineCode(_ code: InlineCode) {
        html += "<code>\(escape(code.code))</code>"
    }
    mutating func visitStrikethrough(_ s: Strikethrough) {
        html += "<del>"; descendInto(s); html += "</del>"
    }
    mutating func visitLink(_ link: Link) {
        html += "<a href=\"\(escape(link.destination ?? "", attribute: true))\"\(titleAttr(link.title))>"
        descendInto(link); html += "</a>"
    }
    mutating func visitImage(_ image: Image) {
        html += "<img src=\"\(escape(image.source ?? "", attribute: true))\" "
            + "alt=\"\(escape(altText(image), attribute: true))\"\(titleAttr(image.title))>"
    }
    mutating func visitCodeBlock(_ block: CodeBlock) {
        // Only the first word of the info string is the language.
        let lang = block.language?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let cls = lang.map { " class=\"language-\(escape($0, attribute: true))\"" } ?? ""
        html += "<pre\(line(block))><code\(cls)>\(escape(block.code))</code></pre>\n"
    }
    mutating func visitBlockQuote(_ quote: BlockQuote) {
        html += "<blockquote\(line(quote))>\n"; descendInto(quote); html += "</blockquote>\n"
    }
    mutating func visitThematicBreak(_ hr: ThematicBreak) { html += "<hr\(line(hr))>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { html += "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { html += "<br>\n" }
    mutating func visitInlineHTML(_ inline: InlineHTML) { html += inline.rawHTML }
    mutating func visitHTMLBlock(_ block: HTMLBlock) { html += block.rawHTML }
    mutating func visitTable(_ table: Table) {
        alignments = table.columnAlignments
        html += "<table\(line(table))>\n"; descendInto(table); html += "</table>\n"
    }
    mutating func visitTableHead(_ head: Table.Head) {
        inHead = true; column = 0
        html += "<thead>\n<tr>\n"; descendInto(head); html += "</tr>\n</thead>\n"
        inHead = false
    }
    mutating func visitTableBody(_ body: Table.Body) {
        guard !body.isEmpty else { return }
        html += "<tbody>\n"; descendInto(body); html += "</tbody>\n"
    }
    mutating func visitTableRow(_ row: Table.Row) {
        column = 0
        html += "<tr>\n"; descendInto(row); html += "</tr>\n"
    }
    mutating func visitTableCell(_ cell: Table.Cell) {
        let tag = inHead ? "th" : "td"
        var style = ""
        if column < alignments.count, let a = alignments[column] {
            switch a {
            case .left: style = " style=\"text-align:left\""
            case .center: style = " style=\"text-align:center\""
            case .right: style = " style=\"text-align:right\""
            }
        }
        html += "<\(tag)\(style)>"; descendInto(cell); html += "</\(tag)>\n"
        column += 1
    }
    mutating func visitUnorderedList(_ list: UnorderedList) {
        tightLists.append(isTight(list))
        html += "<ul>\n"; descendInto(list); html += "</ul>\n"
        tightLists.removeLast()
    }
    mutating func visitOrderedList(_ list: OrderedList) {
        let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
        tightLists.append(isTight(list))
        html += "<ol\(start)>\n"; descendInto(list); html += "</ol>\n"
        tightLists.removeLast()
    }
    mutating func visitListItem(_ item: ListItem) {
        html += "<li\(line(item))>"
        if let box = item.checkbox {
            html += "<input type=\"checkbox\" disabled\(box == .checked ? " checked" : "")> "
        }
        descendInto(item); html += "</li>\n"
    }

    /// ` data-line="N"` for a block when source lines are on, else "".
    private func line(_ node: Markup) -> String {
        guard sourceLines, let r = node.range else { return "" }
        return " data-line=\"\(r.lowerBound.line)\""
    }

    private func titleAttr(_ title: String?) -> String {
        guard let t = title, !t.isEmpty else { return "" }
        return " title=\"\(escape(t, attribute: true))\""
    }

    /// Image alt is plain text: no Markdown syntax, no code-span backticks.
    private func altText(_ node: Markup) -> String {
        node.children.map { child -> String in
            switch child {
            case let t as Text: return t.string
            case let c as InlineCode: return c.code
            case is SoftBreak, is LineBreak: return " "
            default: return altText(child)
            }
        }.joined()
    }

    /// swift-markdown has no tightness API, so derive it from source lines
    /// (CommonMark): loose if a blank line separates two items, or two direct
    /// block children of one item.
    private func isTight(_ list: Markup) -> Bool {
        // cmark item/list ranges can swallow trailing blank lines, so measure a
        // node's end by its deepest last descendant.
        func endLine(_ n: Markup) -> Int? {
            if let last = n.children.reversed().first { return endLine(last) }
            return n.range?.upperBound.line
        }
        func gap(_ a: Markup, _ b: Markup) -> Bool {
            guard let x = endLine(a), let y = b.range?.lowerBound.line else { return false }
            return y > x + 1
        }
        let items = Array(list.children)
        for (i, item) in items.enumerated() {
            if i + 1 < items.count, gap(item, items[i + 1]) { return false }
            let kids = Array(item.children)
            for j in 0..<max(kids.count - 1, 0) where gap(kids[j], kids[j + 1]) { return false }
        }
        return true
    }

    private func escape(_ s: String, attribute: Bool = false) -> String {
        var out = s.replacingOccurrences(of: "&", with: "&amp;")
                   .replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
        if attribute { out = out.replacingOccurrences(of: "\"", with: "&quot;") }
        return out
    }
}
