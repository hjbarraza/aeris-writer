import Foundation
import Markdown

/// A GFM table as raw cell source. Cell strings are the trimmed *source* text
/// (escapes like `\|`, code spans, inline Markdown kept byte-for-byte).
/// Rows are padded to the header's column count by `serialize`: short rows get
/// empty cells. Extra cells beyond the header are kept as written (GFM renders
/// none of them, but they are the user's text, so no edit ever drops them).
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable { case left, center, right }

    public var header: [String]
    public var alignments: [Alignment?]
    public var rows: [[String]]

    public init(header: [String], alignments: [Alignment?], rows: [[String]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }
}

/// Table editing as pure text transforms. Cell coordinates: row 0 is the
/// header, row i ≥ 1 is body row i-1. Every structural operation re-serializes
/// the whole table (aligned pipes) and places the caret in the logically same
/// cell; Tab/⇧Tab only move the selection (except Tab past the last cell).
/// Only top-level tables are handled (not tables inside lists, quotes, code or
/// HTML blocks): the text is parsed from `parseFrom` to the end of the caret's
/// run of non-blank lines. `parseFrom` must be a restart point at or before the
/// caret's line (see `MarkdownCore.isRestartPoint`; never merely the start of
/// that run, which can be a fence's closing line); the default 0 parses
/// everything before the table.
/// The rewritten table uses the line ending of its own first line.
public enum TableEdit {
    public typealias Cell = (row: Int, col: Int)

    // MARK: Parse / serialize

    /// The GFM table containing `caret` (UTF-16), its source range, and the
    /// caret's cell. A caret on the delimiter row maps to the header cell.
    public static func parse(text: String, at caret: Int, parseFrom: Int = 0) -> (table: MarkdownTable, range: NSRange, cell: Cell)? {
        locate(text, caret, parseFrom).map { ($0.table, $0.range, $0.cell) }
    }

    /// The table with aligned pipes, rows joined by "\n" (no trailing newline).
    public static func serialize(_ t: MarkdownTable) -> String { layout(t, eol: "\n").text }

    // MARK: Operations

    /// Insert an empty table (`rows` body rows × `cols` columns, plus an empty
    /// header) at `caret`, padded with blank lines so it parses as a table.
    /// The caret lands in the first header cell.
    public static func insertTable(rows: Int, cols: Int, in text: String, at caret: Int) -> TextEdit {
        let ns = text as NSString
        let eol = LineEnding.of(text)
        let cols = max(cols, 1)
        let t = MarkdownTable(header: Array(repeating: "", count: cols),
                              alignments: Array(repeating: nil, count: cols),
                              rows: Array(repeating: Array(repeating: "", count: cols), count: max(rows, 0)))
        let before = ns.substring(to: caret), after = ns.substring(from: caret)
        let prefix = before.isEmpty ? "" : String(repeating: eol, count: max(0, 2 - trailingBreaks(before)))
        let suffix = after.isEmpty ? "" : String(repeating: eol, count: max(0, 2 - leadingBreaks(after)))
        let l = layout(t, eol: eol)
        let base = caret + (prefix as NSString).length
        return TextEdit(range: NSRange(location: caret, length: 0),
                             replacement: prefix + l.text + suffix,
                             selection: NSRange(location: base + l.cells[0][0].location, length: 0))
    }

    /// Re-align the table's pipes; the caret keeps its place in its cell.
    public static func reformat(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { _, _ in true }
    }

    /// Insert an empty body row above or below the caret's row. On the header
    /// both directions insert the first body row.
    public static func addRow(below: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { t, c in
            let at = c.row == 0 ? 0 : (below ? c.row : c.row - 1)
            t.rows.insert(Array(repeating: "", count: t.header.count), at: at)
            c.row = at + 1
            return true
        }
    }

    /// Delete the caret's body row. The header can't be deleted (nil).
    public static func deleteRow(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { t, c in
            guard c.row > 0 else { return false }
            t.rows.remove(at: c.row - 1)
            c.row = min(c.row, t.rows.count)
            return true
        }
    }

    /// Swap the caret's body row with its neighbour. Rows never swap with the header.
    public static func moveRow(down: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { t, c in
            let target = c.row + (down ? 1 : -1)
            guard c.row > 0, target >= 1, target <= t.rows.count else { return false }
            t.rows.swapAt(c.row - 1, target - 1)
            c.row = target
            return true
        }
    }

    /// Insert an empty, unaligned column before or after the caret's column.
    public static func addColumn(after: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom, columnOp: true) { t, c in
            let at = after ? c.col + 1 : c.col
            t.header.insert("", at: at)
            t.alignments.insert(nil, at: at)
            for i in t.rows.indices { t.rows[i].insert("", at: at) }
            c.col = at
            return true
        }
    }

    /// Delete the caret's column. The last remaining column can't be deleted (nil).
    public static func deleteColumn(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom, columnOp: true) { t, c in
            guard t.header.count > 1 else { return false }
            t.header.remove(at: c.col)
            t.alignments.remove(at: c.col)
            for i in t.rows.indices { t.rows[i].remove(at: c.col) }
            c.col = min(c.col, t.header.count - 1)
            return true
        }
    }

    /// Swap the caret's column (cells and alignment) with its neighbour.
    public static func moveColumn(right: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom, columnOp: true) { t, c in
            let target = c.col + (right ? 1 : -1)
            guard target >= 0, target < t.header.count else { return false }
            t.header.swapAt(c.col, target)
            t.alignments.swapAt(c.col, target)
            for i in t.rows.indices { t.rows[i].swapAt(c.col, target) }
            c.col = target
            return true
        }
    }

    /// Set (or clear, with nil) the alignment of `column`.
    public static func setAlignment(_ alignment: MarkdownTable.Alignment?, column: Int,
                                    in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { t, _ in
            guard t.alignments.indices.contains(column) else { return false }
            t.alignments[column] = alignment
            return true
        }
    }

    /// Set the alignment of the caret's column. A no-op (nil) in an extra cell.
    public static func setAlignment(_ alignment: MarkdownTable.Alignment?, in text: String, at caret: Int,
                                    parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom, columnOp: true) { t, c in
            t.alignments[c.col] = alignment
            return true
        }
    }

    /// Sort by the caret's column (see `sort(column:...)`). A no-op (nil) in an extra cell.
    public static func sort(ascending: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        sortRows(column: nil, ascending: ascending, text, caret, parseFrom)
    }

    /// Stable-sort the body rows by `column`; the header stays. Numeric when
    /// every body cell in the column parses as a number, else localized
    /// case-insensitive. The caret follows its row.
    public static func sort(column: Int, ascending: Bool, in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        sortRows(column: column, ascending: ascending, text, caret, parseFrom)
    }

    /// `column` nil: the caret's column.
    private static func sortRows(column: Int?, ascending: Bool, _ text: String, _ caret: Int, _ parseFrom: Int) -> TextEdit? {
        apply(text, caret, parseFrom, columnOp: column == nil) { t, c in
            let column = column ?? c.col
            guard t.header.indices.contains(column) else { return false }
            let keys = t.rows.map { $0[column] }
            let numbers = keys.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let numeric = numbers.count == keys.count
            func order(_ a: Int, _ b: Int) -> ComparisonResult {
                if numeric { return numbers[a] < numbers[b] ? .orderedAscending : numbers[a] > numbers[b] ? .orderedDescending : .orderedSame }
                return keys[a].localizedCaseInsensitiveCompare(keys[b])
            }
            let perm = t.rows.indices.sorted { a, b in
                let o = order(a, b)
                if o == .orderedSame { return a < b }
                return (o == .orderedAscending) == ascending
            }
            let old = t.rows
            t.rows = perm.map { old[$0] }
            if c.row > 0 { c.row = perm.firstIndex(of: c.row - 1)! + 1 }
            return true
        }
    }

    /// Swap rows and columns: the header becomes the first column. Alignments
    /// reset (they described the old columns). Cell (r, c) moves to (c, r).
    /// Extra cells become extra rows, so nothing is lost.
    public static func transpose(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        apply(text, caret, parseFrom) { t, c in
            let m = [t.header] + t.rows
            let width = m.map(\.count).max() ?? 0
            let tr = (0..<width).map { col in m.map { $0.indices.contains(col) ? $0[col] : "" } }
            t = MarkdownTable(header: tr[0], alignments: Array(repeating: nil, count: m.count), rows: Array(tr.dropFirst()))
            c = (c.col, c.row)
            return true
        }
    }

    /// Tab: select the next cell's content, row by row, without touching the
    /// text (the edit only moves the selection). Past the last cell of the last
    /// row, a new empty row is added (the table is re-serialized) and its first
    /// cell selected.
    public static func nextCell(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        guard let loc = locate(text, caret, parseFrom) else { return nil }
        if let next = loc.sourceCells.first(where: { $0.location > loc.caretCell.location }) {
            return TextEdit(range: NSRange(location: caret, length: 0), replacement: "", selection: next)
        }
        return apply(text, caret, parseFrom, selectCell: true) { t, c in
            t.rows.append(Array(repeating: "", count: t.header.count))
            c = (t.rows.count, 0)
            return true
        }
    }

    /// ⇧Tab: select the previous cell's content (the text is not touched). In
    /// the first header cell the caret stays put; nil only outside a table.
    public static func previousCell(in text: String, at caret: Int, parseFrom: Int = 0) -> TextEdit? {
        guard let loc = locate(text, caret, parseFrom) else { return nil }
        let prev = loc.sourceCells.last(where: { $0.location < loc.caretCell.location }) ?? NSRange(location: caret, length: 0)
        return TextEdit(range: NSRange(location: caret, length: 0), replacement: "", selection: prev)
    }

    /// Cheap test for menu validation: the caret's line has a `|` and
    /// a delimiter row (`|---|`, `:--`) sits among the non-blank lines around it.
    /// No parsing; may say yes for a table-looking line in a code block.
    public static func looksLikeTable(text: String, at caret: Int) -> Bool {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return false }
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        guard ns.substring(with: line).contains("|") else { return false }
        let block = BlockLines.block(ns, at: caret)
        var i = block.location
        while i < NSMaxRange(block) {
            let l = ns.lineRange(for: NSRange(location: i, length: 0))
            if isDelimiterRow(ns.substring(with: contentRange(ns, l))) { return true }
            i = NSMaxRange(l)
        }
        return false
    }

    /// Not supported: GFM tables have no merged cells, and we don't invent
    /// syntax for them. Always nil.
    public static func merge(in text: String, at caret: Int) -> TextEdit? { nil }

    /// Not supported (see `merge`). Always nil.
    public static func unmerge(in text: String, at caret: Int) -> TextEdit? { nil }

    // MARK: Internals

    private struct Located {
        var table: MarkdownTable
        var range: NSRange
        var cell: Cell
        /// Caret offset inside the cell's trimmed content (UTF-16).
        var inner: Int
        /// Every cell's content range in the source (absolute UTF-16), header
        /// then body rows, in document order.
        var sourceCells: [NSRange]
        /// The caret's cell among `sourceCells` (a header cell on the delimiter row).
        var caretCell: NSRange
        /// The caret's column when it is in a cell beyond the header's (`cell` is clamped).
        var extraCol: Int?
    }

    /// A row's cells as written, split on unescaped pipes (GFM's rule; leading
    /// and trailing pipes optional): each cell's segment between pipes and its
    /// trimmed content (an empty cell's content is an empty range one space in).
    private static func splitCells(_ ns: NSString, _ line: NSRange) -> [(segment: NSRange, content: NSRange)] {
        func isSpace(_ i: Int) -> Bool { let u = ns.character(at: i); return u == 0x20 || u == 0x09 }
        var i = line.location, end = NSMaxRange(line)
        while i < end, isSpace(i) { i += 1 }
        while end > i, isSpace(end - 1) { end -= 1 }
        guard i < end else { return [] }
        if ns.character(at: i) == 0x7C { i += 1 }
        var segments: [NSRange] = [], start = i
        while i < end {
            let u = ns.character(at: i)
            // GFM's row scanner: only a backslash before a pipe escapes it, so
            // `\\|` is a plain backslash then an escaped pipe.
            if u == 0x5C, i + 1 < end, ns.character(at: i + 1) == 0x7C { i += 2; continue }
            if u == 0x7C {
                segments.append(NSRange(location: start, length: i - start))
                start = i + 1
            }
            i += 1
        }
        if start < end || segments.isEmpty { segments.append(NSRange(location: start, length: max(end - start, 0))) }
        return segments.map { seg in
            var a = seg.location, b = NSMaxRange(seg)
            while a < b, isSpace(a) { a += 1 }
            while b > a, isSpace(b - 1) { b -= 1 }
            if a == b { a = min(seg.location + 1, NSMaxRange(seg)); b = a }
            return (seg, NSRange(location: a, length: b - a))
        }
    }

    /// `line` (from `lineRange`) without its terminator.
    private static func contentRange(_ ns: NSString, _ line: NSRange) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location, ns.character(at: end - 1) == 0x0A || ns.character(at: end - 1) == 0x0D { end -= 1 }
        return NSRange(location: line.location, length: end - line.location)
    }

    private static func isDelimiterRow(_ s: String) -> Bool {
        s.range(of: #"^[ \t]*\|?([ \t]*:?-+:?[ \t]*\|)*[ \t]*:?-+:?[ \t]*\|?[ \t]*$"#, options: .regularExpression) != nil
    }

    private static func locate(_ text: String, _ caret: Int, _ parseFrom: Int) -> Located? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        // A table never spans a blank line, so the parse stops at the end of the
        // caret's run of non-blank lines. It starts at `parseFrom`, so what comes
        // before (an open fence, an HTML block, a list) decides whether this is a
        // top-level table.
        let block = BlockLines.block(ns, at: caret)
        let from = min(max(parseFrom, 0), caret)
        let source = NSRange(location: from, length: NSMaxRange(block) - from)
        let sub = ns.substring(with: source)
        let conv = SpanCollector(sub)
        for case let table as Table in MarkdownCore.parse(sub).children {
            guard let sr = table.range else { continue }
            let start = source.location + conv.utf16Offset(sr.lowerBound)
            let end = source.location + conv.utf16Offset(sr.upperBound)
            guard caret >= start, caret <= end else { continue }

            // The table's source lines. Cells come from the source, not the
            // parser, so extra cells (which swift-markdown discards) are kept.
            var lines: [NSRange] = []
            var i = start
            repeat {
                let l = ns.lineRange(for: NSRange(location: i, length: 0))
                lines.append(contentRange(ns, l))
                i = NSMaxRange(l)
            } while i < end
            guard lines.count >= 2 else { continue }
            let range = NSRange(location: lines[0].location, length: NSMaxRange(lines[lines.count - 1]) - lines[0].location)
            let cells = lines.map { splitCells(ns, $0) }
            let raw = ([cells[0]] + cells.dropFirst(2)).map { $0.map { ns.substring(with: $0.content) } }
            let cols = max(raw[0].count, 1)
            func padded(_ r: [String]) -> [String] { r + Array(repeating: "", count: max(0, cols - r.count)) }
            var aligns: [MarkdownTable.Alignment?] = table.columnAlignments.map {
                switch $0 { case .left?: return .left; case .center?: return .center; case .right?: return .right; case nil: return nil }
            }
            aligns = Array((aligns + Array(repeating: nil, count: cols)).prefix(cols))
            let t = MarkdownTable(header: padded(raw[0]), alignments: aligns, rows: raw.dropFirst().map(padded))

            // Row from the line (the delimiter row maps to the header); column:
            // the first cell whose segment ends at or after the caret.
            let k = lines.firstIndex { caret <= NSMaxRange($0) } ?? lines.count - 1
            let row = k <= 1 ? 0 : k - 1
            let col = max(cells[k].firstIndex { caret <= NSMaxRange($0.segment) } ?? cells[k].count - 1, 0)
            let rowCells = cells[k == 1 ? 0 : k].map(\.content)
            let caretCell = rowCells.isEmpty ? NSRange(location: caret, length: 0) : rowCells[min(col, rowCells.count - 1)]
            let inner = k == 1 ? 0 : min(max(caret - caretCell.location, 0), caretCell.length)
            let sourceCells = ([cells[0]] + cells.dropFirst(2)).flatMap { $0.map(\.content) }
            return Located(table: t, range: range, cell: (row, min(col, cols - 1)), inner: inner,
                           sourceCells: sourceCells, caretCell: caretCell, extraCol: col >= cols ? col : nil)
        }
        return nil
    }

    /// Locate the table, run `transform` on it and the caret cell (false → nil),
    /// re-serialize, and place the selection: the whole cell content when
    /// `selectCell`, else a caret at the same offset inside the cell (clamped).
    /// `columnOp`: the operation acts on the caret's column. With the caret in an
    /// extra cell (beyond the header's columns, which no column operation can
    /// address) it is a no-op (nil) rather than acting on the last real column.
    private static func apply(_ text: String, _ caret: Int, _ parseFrom: Int, selectCell: Bool = false, columnOp: Bool = false,
                              _ transform: (inout MarkdownTable, inout Cell) -> Bool) -> TextEdit? {
        guard var loc = locate(text, caret, parseFrom), !(columnOp && loc.extraCol != nil) else { return nil }
        let col = loc.cell.col
        guard transform(&loc.table, &loc.cell) else { return nil }
        let eol = LineEnding.of((text as NSString).substring(with: loc.range))
        let l = layout(loc.table, eol: eol)
        // A caret in an extra cell stays there unless the operation moved its column.
        if loc.cell.col == col, l.cells[loc.cell.row].indices.contains(loc.extraCol ?? -1) { loc.cell.col = loc.extraCol! }
        let cell = l.cells[loc.cell.row][loc.cell.col]
        let sel = selectCell ? cell : NSRange(location: cell.location + min(loc.inner, cell.length), length: 0)
        return TextEdit(range: loc.range, replacement: l.text,
                             selection: NSRange(location: loc.range.location + sel.location, length: sel.length))
    }

    /// Serialized text plus each cell's content range (UTF-16, relative to the
    /// table start), indexed [row][col] with row 0 = header.
    private static func layout(_ t: MarkdownTable, eol: String) -> (text: String, cells: [[NSRange]]) {
        let cols = max(t.header.count, 1)
        // Short rows are padded; extra cells are kept (in columns of their own width).
        func fit(_ r: [String]) -> [String] { r + Array(repeating: "", count: max(0, cols - r.count)) }
        let grid = ([t.header] + t.rows).map(fit)
        let aligns = Array((t.alignments + Array(repeating: nil, count: cols)).prefix(cols))
        let widths = (0..<(grid.map(\.count).max() ?? cols)).map { c -> Int in
            let colons = c >= cols || aligns[c] == nil ? 0 : aligns[c] == .center ? 2 : 1
            return max(3 + colons, grid.map { $0.indices.contains(c) ? displayWidth($0[c]) : 0 }.max() ?? 0)
        }
        var text = "", cells: [[NSRange]] = []
        func line(_ items: [String]) -> [NSRange] {
            var ranges: [NSRange] = []
            text += "|"
            for (c, s) in items.enumerated() {
                text += " "
                ranges.append(NSRange(location: (text as NSString).length, length: (s as NSString).length))
                text += s + String(repeating: " ", count: widths[c] - displayWidth(s)) + " |"
            }
            return ranges
        }
        cells.append(line(grid[0]))
        text += eol
        _ = line((0..<cols).map { c in
            let w = widths[c]
            switch aligns[c] {
            case .left?: return ":" + String(repeating: "-", count: w - 1)
            case .center?: return ":" + String(repeating: "-", count: w - 2) + ":"
            case .right?: return String(repeating: "-", count: w - 1) + ":"
            case nil: return String(repeating: "-", count: w)
            }
        })
        for r in grid.dropFirst() {
            text += eol
            cells.append(line(r))
        }
        return (text, cells)
    }

    /// Monospace display width. Heuristic per grapheme cluster: 2 if it is an
    /// emoji presentation (default-emoji scalar, or any emoji followed by VS16
    /// U+FE0F) or starts with an East Asian Wide/Fullwidth scalar (CJK, Hangul,
    /// kana, fullwidth forms — fixed ranges below), else 1.
    static func displayWidth(_ s: String) -> Int {
        s.reduce(0) { sum, ch in
            let scalars = ch.unicodeScalars
            guard let first = scalars.first else { return sum }
            let emoji = scalars.contains { $0.properties.isEmojiPresentation }
                || (first.properties.isEmoji && scalars.contains { $0.value == 0xFE0F })
            return sum + (emoji || isWide(first.value) ? 2 : 1)
        }
    }

    private static func isWide(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x2FFFD, 0x30000...0x3FFFD: return true
        default: return false
        }
    }

    /// Line breaks (up to 2) at the end / start of `s`. A CRLF counts once.
    private static func trailingBreaks(_ s: String) -> Int {
        var n = 0
        for ch in s.reversed() { guard ch.isNewline, n < 2 else { break }; n += 1 }
        return n
    }
    private static func leadingBreaks(_ s: String) -> Int {
        var n = 0
        for ch in s { guard ch.isNewline, n < 2 else { break }; n += 1 }
        return n
    }
}
