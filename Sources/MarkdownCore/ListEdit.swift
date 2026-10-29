import Foundation
import Markdown

/// Pure range maths for list commands: toggling, Return continuation, indent.
public enum ListEdit {
    public enum Kind: Sendable { case bullet, ordered, task, orderedTask }

    /// A parsed list-item line. Offsets are UTF-16 within the line.
    private struct Item {
        let indent: String
        let bulletChar: String?   // "-", "*", "+" for bullets
        let number: Int?          // for ordered items
        let delim: String         // "." or ")" for ordered items
        let task: String?         // "[ ]" / "[x]"
        let contentStart: Int
        let content: String
        let markerWidth: Int      // marker + one space: the item's content indent

        func matches(_ k: Kind) -> Bool {
            switch k {
            case .bullet: return number == nil && task == nil
            case .ordered: return number != nil && task == nil
            case .task: return number == nil && task != nil
            case .orderedTask: return number != nil && task != nil
            }
        }
    }

    /// Compiled once: renumbering parses every line of a list per keystroke.
    nonisolated(unsafe) private static let itemPattern =
        try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+|$)(?:(\[[ xX]\])([ \t]+|$))?(.*)$"#)

    private static func parse(_ s: String) -> Item? {
        guard let m = itemPattern.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        else { return nil }
        let c = (0..<m.numberOfRanges).map { m.range(at: $0) }
        let marker = BlockLines.sub(s, c[2]) ?? ""
        return Item(indent: BlockLines.sub(s, c[1]) ?? "",
                    bulletChar: c[3].location == NSNotFound ? marker : nil,
                    number: BlockLines.sub(s, c[3]).flatMap { Int($0) },
                    delim: BlockLines.sub(s, c[4]) ?? ".",
                    task: BlockLines.sub(s, c[6]),
                    contentStart: c[8].location,
                    content: BlockLines.sub(s, c[8]) ?? "",
                    markerWidth: marker.utf16.count + 1)
    }

    // MARK: Toggle

    /// Converts touched lines to `kind`, or strips the markers if they all already are.
    /// Ordered numbering starts at 1 and counts non-blank lines. Existing task
    /// state and bullet characters are kept.
    public static func toggleList(_ kind: Kind, text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text)
        let t = BlockLines.touched(lines, selection)
        let multi = t.last > t.first
        let body = lines[t.first...t.last].map(\.content).filter { !BlockLines.isBlank($0) }
        let allSame = !body.isEmpty && body.allSatisfy { parse($0)?.matches(kind) == true }
        var n = 0
        return BlockLines.apply(lines, t, selection) { _, s in
            if multi && BlockLines.isBlank(s) { return s }
            let item = parse(s)
            if allSame, let item { return item.indent + item.content }
            let indent = item?.indent ?? String(s.prefix { $0 == " " || $0 == "\t" })
            let content = item?.content ?? String(s.dropFirst(indent.count))
            n += 1
            let marker: String
            switch kind {
            case .bullet, .task: marker = item?.bulletChar ?? "-"
            case .ordered, .orderedTask: marker = "\(n)\(item?.number != nil ? item!.delim : ".")"
            }
            let box = (kind == .task || kind == .orderedTask) ? (item?.task ?? "[ ]") + " " : ""
            return indent + marker + " " + box + content
        }
    }

    // MARK: Return

    /// What Return does at a caret, or nil when it should behave normally.
    /// Continues list items (bullet char kept, ordered +1, new tasks unchecked)
    /// and blockquotes; Return on an empty item/quote line clears the line.
    /// The ordered items below are renumbered in the same edit (see `renumberBelow`).
    /// A setext underline (`-` under a paragraph line) is not an item. Code blocks
    /// are the caller's to exclude.
    public static func newline(text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let lines = BlockLines.split(text, around: selection, linesBefore: Self.paragraphLookback)
        let li = BlockLines.touched(lines, selection).first
        let line = lines[li]
        let col = selection.location - line.start
        let eol = LineEnding.of(text)
        if isSetextUnderline(lines, li) { return nil }

        func clear() -> TextEdit {
            TextEdit(range: NSRange(location: line.start, length: line.length), replacement: "",
                          selection: NSRange(location: line.start, length: 0))
        }
        func insert(_ prefix: String) -> TextEdit {
            let rep = eol + prefix
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: rep,
                                 selection: NSRange(location: selection.location + rep.utf16.count, length: 0))
        }

        if let item = parse(line.content) {
            guard col >= item.contentStart else { return nil }
            if BlockLines.isBlank(item.content) { return renumbered(text, clear()) }
            var marker: String
            if let n = item.number { marker = "\(n + 1)\(item.delim)" } else { marker = item.bulletChar ?? "-" }
            marker += " "
            if item.task != nil { marker += "[ ] " }
            return renumbered(text, insert(item.indent + marker))
        }
        if let c = BlockLines.captures(#"^([ \t]{0,3}(?:>[ \t]?)+)(.*)$"#, line.content) {
            let prefixLen = c[1].length
            guard col >= prefixLen else { return nil }
            if BlockLines.isBlank(BlockLines.sub(line.content, c[2]) ?? "") { return clear() }
            return insert(BlockLines.sub(line.content, c[1]) ?? "> ")
        }
        return nil
    }

    // MARK: Renumbering

    /// Deleting `range` when it removes a line break: the deletion plus the
    /// renumbering of the ordered items below it, as one edit. Nil when nothing
    /// needs renumbering (the caller deletes normally). Code blocks are the
    /// caller's to exclude.
    public static func delete(text: String, range: NSRange) -> TextEdit? {
        let removed = (text as NSString).substring(with: range)
        guard removed.utf16.contains(where: { $0 == 0x0A || $0 == 0x0D }) else { return nil }
        let edit = TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
        let result = renumbered(text, edit)
        return result == edit ? nil : result
    }

    /// `edit` plus the renumbering of the ordered list it touches, as one edit.
    /// Only a list that was sequential before the edit (from the anchor item down,
    /// each sibling = previous + 1) is renumbered: a `1. 1. 1.` list or hand-picked
    /// numbers (years, references) are never rewritten. After the edit the anchor
    /// line takes the anchor's old number (so deleting a list's first item
    /// renumbers the rest from it) and its siblings below count up from there.
    /// The whole text is copied only once the edit is known to be in such a list.
    private static func renumbered(_ text: String, _ edit: TextEdit) -> TextEdit {
        let old = text as NSString
        guard let a = anchor(old, at: edit.range.location), let start = a.item.number else { return edit }
        var expect = start
        for (num, _) in siblings(old, of: a) {
            expect += 1
            guard num == expect else { return edit }
        }
        let new = NSMutableString(string: text)
        new.replaceCharacters(in: edit.range, with: edit.replacement)
        let line = new.lineRange(for: NSRange(location: a.line.location, length: 0))
        guard let item = parse(content(new, line)), let first = item.number,
              item.indent == a.item.indent, item.delim == a.item.delim else { return edit }
        var changes: [(NSRange, String)] = []
        if first != start { changes.append((digits(line, item), "\(start)")) }
        var n = start
        for (num, r) in siblings(new, of: (line, item)) {
            n += 1
            if num != n { changes.append((r, "\(n)")) }
        }
        let at = edit.range.location + edit.replacement.utf16.count
        guard let head = changes.first?.0, head.location >= at else { return edit }
        var rep = "", pos = head.location
        for (r, s) in changes {
            rep += new.substring(with: NSRange(location: pos, length: r.location - pos)) + s
            pos = NSMaxRange(r)
        }
        let delta = edit.replacement.utf16.count - edit.range.length
        let between = new.substring(with: NSRange(location: edit.range.location, length: head.location - edit.range.location))
        return TextEdit(range: NSRange(location: edit.range.location, length: pos - delta - edit.range.location),
                        replacement: between + rep, selection: edit.selection)
    }

    /// A line's text without its terminator.
    private static func content(_ ns: NSString, _ r: NSRange) -> String {
        var s = ns.substring(with: r)
        while s.hasSuffix("\n") || s.hasSuffix("\r") || s.hasSuffix("\r\n") { s.removeLast() }
        return s
    }

    /// The UTF-16 range of an ordered item's number on its line.
    private static func digits(_ line: NSRange, _ item: Item) -> NSRange {
        NSRange(location: line.location + item.indent.utf16.count, length: item.markerWidth - 2)
    }

    /// The ordered item an edit at `p` belongs to: the item on the line holding
    /// `p`, or above it past blank and more-indented lines. When `p` starts a line
    /// the search starts on the line above (the item `p`'s line follows); if that
    /// finds none, `p`'s own line is the anchor when it is an ordered item (a
    /// list's first item). Looks up at most 1000 lines.
    private static func anchor(_ ns: NSString, at p: Int) -> (line: NSRange, item: Item)? {
        func line(_ i: Int) -> NSRange { ns.lineRange(for: NSRange(location: i, length: 0)) }
        func leading(_ s: String) -> Int { s.prefix { $0 == " " || $0 == "\t" }.count }
        var cur = line(min(p, ns.length))
        var target: Int?
        var own: (line: NSRange, item: Item)?
        if p == cur.location, p > 0 {
            if let item = parse(content(ns, cur)), item.number != nil {
                target = item.indent.count
                own = (cur, item)
            }
            cur = line(p - 1)
        }
        for _ in 0..<1000 {
            let s = content(ns, cur)
            if !BlockLines.isBlank(s) {
                let item = parse(s)
                let indent = item?.indent.count ?? leading(s)
                if let item, item.number != nil, target == nil || indent == target { return (cur, item) }
                // Nested lines are skipped; an item or text at the list's level ends it.
                guard item == nil ? indent > (target ?? 0) : indent > (target ?? Int.max) else { return own }
            }
            guard cur.location > 0 else { return own }
            cur = line(cur.location - 1)
        }
        return own
    }

    /// The anchor's sibling items below it (same indent and delimiter; nested and
    /// blank lines skipped) as (number, digits range). The list ends at any other line.
    private static func siblings(_ ns: NSString, of anchor: (line: NSRange, item: Item)) -> [(Int, NSRange)] {
        let indent = anchor.item.indent.count
        var out: [(Int, NSRange)] = []
        var pos = NSMaxRange(anchor.line)
        while pos < ns.length {
            let r = ns.lineRange(for: NSRange(location: pos, length: 0))
            pos = NSMaxRange(r)
            let s = content(ns, r)
            if BlockLines.isBlank(s) { continue }
            if let item = parse(s) {
                if item.indent.count > indent { continue }
                guard item.indent.count == indent, let num = item.number, item.delim == anchor.item.delim else { break }
                out.append((num, digits(r, item)))
            } else if s.prefix(while: { $0 == " " || $0 == "\t" }).count <= indent {
                break
            }
        }
        return out
    }

    // MARK: Indent / outdent

    /// List items indent by their content width (2 for `- `, 3 for `1. `);
    /// other lines by 4 spaces. Blank lines in a multi-line selection are skipped.
    public static func indent(text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text, around: selection)
        let t = BlockLines.touched(lines, selection)
        let multi = t.last > t.first
        return BlockLines.apply(lines, t, selection) { _, s in
            if multi && BlockLines.isBlank(s) { return s }
            let width = parse(s)?.markerWidth ?? 4
            return String(repeating: " ", count: width) + s
        }
    }

    /// Removes one leading tab, or leading spaces: a nested list item moves to
    /// its parent item's indentation (the nearest earlier item indented less);
    /// other lines lose up to one indent step (item content width, else 4).
    /// The parent is looked for in the 1000 lines above.
    public static func outdent(text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text, around: selection, linesBefore: 1000)
        let t = BlockLines.touched(lines, selection)
        return BlockLines.apply(lines, t, selection) { i, s in
            if s.hasPrefix("\t") { return String(s.dropFirst()) }
            let spaces = s.prefix { $0 == " " }.count
            let item = parse(s)
            if item != nil, spaces > 0,
               let parent = lines[..<(t.first + i)].reversed().lazy.compactMap({ parse($0.content) })
                   .first(where: { $0.indent.count < spaces }) {
                return parent.indent + String(s.dropFirst(spaces))
            }
            return String(s.dropFirst(min(spaces, item?.markerWidth ?? 4)))
        }
    }

    /// True when the line holding the selection's start is a list item (not a
    /// setext underline).
    public static func isItem(text: String, selection: NSRange) -> Bool {
        let lines = BlockLines.split(text, around: NSRange(location: selection.location, length: 0), linesBefore: Self.paragraphLookback)
        let li = BlockLines.touched(lines, NSRange(location: selection.location, length: 0)).first
        return parse(lines[li].content) != nil && !isSetextUnderline(lines, li)
    }

    /// Lines read above the caret to tell a setext underline from a list item.
    static let paragraphLookback = 50

    /// A lone `-` (or `=`) run under a top-level paragraph line underlines a
    /// setext heading. The line above is such a line unless blank, a list item, a
    /// quote, an ATX heading, a fence or a table row, or unless the paragraph it
    /// belongs to (the non-blank lines above it) started in a list item or a
    /// quote: then the underline would sit outside that container, so it is a
    /// new list item, not an underline.
    private static func isSetextUnderline(_ lines: [BlockLine], _ i: Int) -> Bool {
        guard i > 0, lines[i].content.range(of: #"^ {0,3}(-+|=+)[ \t]*$"#, options: .regularExpression) != nil
        else { return false }
        let above = lines[i - 1].content
        guard !BlockLines.isBlank(above), parse(above) == nil,
              above.range(of: #"^ {0,3}([>#|]|```|~~~)"#, options: .regularExpression) == nil else { return false }
        for line in lines[..<(i - 1)].reversed() {
            if BlockLines.isBlank(line.content) { break }
            if parse(line.content) != nil || line.content.range(of: #"^ {0,3}>"#, options: .regularExpression) != nil {
                return false
            }
        }
        return true
    }

    // MARK: Checkbox click

    /// Flips the `[ ]` / `[x]` of the task item whose box holds `index` (a click's
    /// insertion index, so either edge of the box counts); nil anywhere else. Task
    /// items come from swift-markdown (`ListItem.checkbox`), so a `[ ]` in code or
    /// in plain text is never a box. The caret stays at `index`.
    public static func toggleCheckbox(text: String, at index: Int) -> TextEdit? {
        let s = text as NSString
        let conv = SpanCollector(text)
        var hit: TextEdit?
        func walk(_ m: Markup) {
            if let item = m as? ListItem, let box = item.checkbox, let r = conv.nsRange(item.range) {
                // The box is the first `[` after the item's marker, on its first line.
                let line = s.lineRange(for: NSRange(location: r.location, length: 0))
                let b = s.range(of: "[", range: NSRange(location: r.location, length: NSMaxRange(line) - r.location))
                if b.location != NSNotFound, b.location <= index, index <= b.location + 3 {
                    hit = TextEdit(range: NSRange(location: b.location + 1, length: 1),
                                   replacement: box == .checked ? " " : "x",
                                   selection: NSRange(location: index, length: 0))
                }
            }
            m.children.forEach(walk)
        }
        walk(MarkdownCore.parse(text))
        return hit
    }
}
