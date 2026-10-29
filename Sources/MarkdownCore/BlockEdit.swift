import Foundation
import Markdown

/// One source line: `content` excludes the terminator (LF, CRLF or CR).
struct BlockLine {
    let start: Int
    let content: String
    let length: Int
    let terminator: String
}

/// Line-splitting and per-line editing helpers shared by `BlockEdit` and `ListEdit`.
enum BlockLines {
    /// Always returns at least one line (an empty document is one empty line).
    static func split(_ text: String) -> [BlockLine] {
        let ns = text as NSString
        let n = ns.length
        var out: [BlockLine] = []
        var start = 0, i = 0
        while i < n {
            let c = ns.character(at: i)
            if c == 0x0A || c == 0x0D {
                let termLen = (c == 0x0D && i + 1 < n && ns.character(at: i + 1) == 0x0A) ? 2 : 1
                out.append(BlockLine(start: start, content: ns.substring(with: NSRange(location: start, length: i - start)),
                                     length: i - start, terminator: ns.substring(with: NSRange(location: i, length: termLen))))
                i += termLen
                start = i
            } else {
                i += 1
            }
        }
        out.append(BlockLine(start: start, content: ns.substring(from: start), length: n - start, terminator: ""))
        return out
    }

    /// The lines touched by `selection` plus up to `linesBefore` lines above them,
    /// with offsets into the whole text: what keystroke commands split instead of
    /// the whole document. Same line breaks as `split` (LF, CRLF, CR).
    static func split(_ text: String, around selection: NSRange, linesBefore: Int = 0) -> [BlockLine] {
        let ns = text as NSString
        let n = ns.length
        func isBreak(_ i: Int) -> Bool { let c = ns.character(at: i); return c == 0x0A || c == 0x0D }
        func lineStart(_ i: Int) -> Int { var j = i; while j > 0, !isBreak(j - 1) { j -= 1 }; return j }
        let loc = min(max(selection.location, 0), n)
        var start = lineStart(loc)
        for _ in 0..<linesBefore where start > 0 {
            var j = start - 1  // the previous line's terminator; CRLF counts once
            if j > 0, ns.character(at: j) == 0x0A, ns.character(at: j - 1) == 0x0D { j -= 1 }
            start = lineStart(j)
        }
        var end = min(loc + max(selection.length, 0), n)
        while end < n, !isBreak(end) { end += 1 }
        if end < n { end += ns.character(at: end) == 0x0D && end + 1 < n && ns.character(at: end + 1) == 0x0A ? 2 : 1 }
        return split(ns.substring(with: NSRange(location: start, length: end - start))).map {
            BlockLine(start: $0.start + start, content: $0.content, length: $0.length, terminator: $0.terminator)
        }
    }

    static func isBlank(_ s: String) -> Bool {
        s.allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// The run of non-blank lines around `offset` (UTF-16), terminators included;
    /// on a blank line, that line alone. What keystroke commands parse instead of
    /// the whole document.
    static func block(_ ns: NSString, at offset: Int) -> NSRange {
        func line(_ i: Int) -> NSRange { ns.lineRange(for: NSRange(location: i, length: 0)) }
        func isBlankLine(_ r: NSRange) -> Bool {
            for i in r.location..<NSMaxRange(r) {
                let u = ns.character(at: i)
                if u != 0x20, u != 0x09, u != 0x0A, u != 0x0D { return false }
            }
            return true
        }
        let first = line(min(max(offset, 0), ns.length))
        guard !isBlankLine(first) else { return first }
        var lo = first.location, hi = NSMaxRange(first)
        while lo > 0 {
            let prev = line(lo - 1)
            if isBlankLine(prev) { break }
            lo = prev.location
        }
        while hi < ns.length {
            let next = line(hi)
            if isBlankLine(next) { break }
            hi = NSMaxRange(next)
        }
        return NSRange(location: lo, length: hi - lo)
    }

    /// Index of the line containing `offset`.
    static func index(_ lines: [BlockLine], at offset: Int) -> Int {
        var idx = 0
        for (i, l) in lines.enumerated() where l.start <= offset { idx = i }
        return idx
    }

    /// First and last line touched by `selection`; a selection ending exactly at
    /// the start of a later line does not touch that line.
    static func touched(_ lines: [BlockLine], _ selection: NSRange) -> (first: Int, last: Int) {
        let total = lines[lines.count - 1].start + lines[lines.count - 1].length
        let loc = min(max(selection.location, 0), total)
        let first = index(lines, at: loc)
        guard selection.length > 0 else { return (first, first) }
        let end = min(loc + selection.length, total)
        var last = index(lines, at: end)
        if last > first && lines[last].start == end { last -= 1 }
        return (first, last)
    }

    /// Rewrites each touched line's content. Empty selection: caret keeps its
    /// distance from the line end. Non-empty: the rewritten block is selected.
    static func apply(_ lines: [BlockLine], _ f: (first: Int, last: Int), _ selection: NSRange,
                      _ transform: (_ index: Int, _ content: String) -> String) -> TextEdit {
        let a = lines[f.first].start
        let end = lines[f.last].start + lines[f.last].length
        var rep = ""
        var caret = a
        for i in f.first...f.last {
            let l = lines[i]
            let before = rep.utf16.count
            let nc = transform(i - f.first, l.content)
            rep += nc
            if i == f.first && selection.length == 0 {
                let dist = max(0, l.length - (selection.location - l.start))
                caret = a + before + max(0, nc.utf16.count - dist)
            }
            if i < f.last { rep += l.terminator }
        }
        let sel = selection.length == 0 ? NSRange(location: caret, length: 0)
                                        : NSRange(location: a, length: rep.utf16.count)
        return TextEdit(range: NSRange(location: a, length: end - a), replacement: rep, selection: sel)
    }

    /// Capture-group ranges (NSNotFound location for groups that did not match).
    static func captures(_ pattern: String, _ s: String) -> [NSRange]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0) }
    }

    static func sub(_ s: String, _ r: NSRange) -> String? {
        r.location == NSNotFound ? nil : (s as NSString).substring(with: r)
    }
}

/// Pure range maths for block-level formatting commands. No AppKit.
public enum BlockEdit {
    // MARK: Headings

    /// Sets the ATX heading level on every touched line; a line already at
    /// exactly `level` loses its heading. Level 0 removes headings.
    public static func heading(_ level: Int, text: String, selection: NSRange) -> TextEdit {
        let lvl = min(max(level, 0), 6)
        let lines = BlockLines.split(text)
        let t = BlockLines.touched(lines, selection)
        let multi = t.last > t.first
        return BlockLines.apply(lines, t, selection) { _, s in
            if multi && BlockLines.isBlank(s) { return s }
            var cur = 0, rest = s
            if let c = BlockLines.captures(#"^ {0,3}(#{1,6})(?:[ \t]+|$)(.*)$"#, s) {
                cur = c[1].length
                rest = BlockLines.sub(s, c[2]) ?? ""
            }
            if lvl == 0 || cur == lvl { return rest }
            return String(repeating: "#", count: lvl) + " " + rest
        }
    }

    // MARK: Quote and callout

    /// Prefixes touched lines with `> `; removes one level if all already quoted.
    public static func quote(text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text)
        let t = BlockLines.touched(lines, selection)
        let body = lines[t.first...t.last].map(\.content).filter { !BlockLines.isBlank($0) }
        let allQuoted = !body.isEmpty && body.allSatisfy { $0.range(of: #"^ {0,3}>"#, options: .regularExpression) != nil }
        let multi = t.last > t.first
        return BlockLines.apply(lines, t, selection) { _, s in
            if allQuoted {
                return s.replacingOccurrences(of: #"^( {0,3})> ?"#, with: "$1", options: .regularExpression)
            }
            return (multi && BlockLines.isBlank(s)) ? ">" : "> " + s
        }
    }

    /// GFM alert: `> [!KIND]` then the touched lines quoted. If the first touched
    /// line is already an alert header, only its kind changes (no toggle off).
    public static func callout(kind: String, text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text)
        let t = BlockLines.touched(lines, selection)
        let header = "> [!\(kind)]"
        let first = lines[t.first]
        if first.content.range(of: #"^> \[![A-Z]+\]\s*$"#, options: .regularExpression) != nil {
            return TextEdit(range: NSRange(location: first.start, length: first.length), replacement: header,
                                 selection: NSRange(location: first.start + header.utf16.count, length: 0))
        }
        let eol = LineEnding.of(text)
        let a = first.start
        let end = lines[t.last].start + lines[t.last].length
        let body = lines[t.first...t.last].map { (t.last > t.first && BlockLines.isBlank($0.content)) ? ">" : "> " + $0.content }
        let rep = ([header] + body).joined(separator: eol)
        let n = rep.utf16.count
        let sel = selection.length == 0 ? NSRange(location: a + n, length: 0) : NSRange(location: a, length: n)
        return TextEdit(range: NSRange(location: a, length: end - a), replacement: rep, selection: sel)
    }

    // MARK: Fenced blocks

    /// Wraps the touched lines in ``` fences; unwraps if they are exactly a fenced block.
    public static func codeFence(text: String, selection: NSRange) -> TextEdit {
        wrap("```", text: text, selection: selection)
    }

    /// Wraps the touched lines in `$$` lines; unwraps if they are exactly a `$$` block.
    public static func displayMath(text: String, selection: NSRange) -> TextEdit {
        wrap("$$", text: text, selection: selection)
    }

    private static func wrap(_ delim: String, text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text)
        let t = BlockLines.touched(lines, selection)
        let a = lines[t.first].start
        let end = lines[t.last].start + lines[t.last].length
        let open = lines[t.first].content.trimmingCharacters(in: .whitespaces)
        let close = lines[t.last].content.trimmingCharacters(in: .whitespaces)
        let opens = delim == "$$" ? open == "$$" : open.hasPrefix(delim)
        if t.last > t.first && opens && close == delim {
            var inner = ""
            if t.last - t.first > 1 {
                for i in (t.first + 1)..<t.last {
                    inner += lines[i].content
                    if i < t.last - 1 { inner += lines[i].terminator }
                }
            }
            return TextEdit(range: NSRange(location: a, length: end - a), replacement: inner,
                                 selection: NSRange(location: a, length: inner.utf16.count))
        }
        let eol = LineEnding.of(text)
        let block = (text as NSString).substring(with: NSRange(location: a, length: end - a))
        let openLen = delim.utf16.count + eol.utf16.count
        let sel: NSRange
        if block.isEmpty {
            sel = NSRange(location: a + openLen, length: 0)
        } else {
            sel = NSRange(location: min(max(selection.location, 0), end) + openLen, length: selection.length)
        }
        return TextEdit(range: NSRange(location: a, length: end - a),
                             replacement: delim + eol + block + eol + delim, selection: sel)
    }

    // MARK: Inserted blocks

    public static func horizontalRule(text: String, selection: NSRange) -> TextEdit {
        insertBlock("---", text: text, selection: selection)
    }

    public static func pageBreak(text: String, selection: NSRange) -> TextEdit {
        insertBlock(#"<div style="page-break-after: always"></div>"#, text: text, selection: selection)
    }

    /// Inserts `block` on its own line after the last touched line, separated by
    /// blank lines so `---` never turns the previous line into a setext heading.
    private static func insertBlock(_ block: String, text: String, selection: NSRange) -> TextEdit {
        let lines = BlockLines.split(text)
        let l = BlockLines.touched(lines, selection).last
        let eol = LineEnding.of(text)
        let line = lines[l]
        let p = line.start + line.length
        var prefix = ""
        if !BlockLines.isBlank(line.content) {
            prefix = eol + eol
        } else if l > 0 && !BlockLines.isBlank(lines[l - 1].content) {
            prefix = eol
        }
        let nextIsText = l + 1 < lines.count && !BlockLines.isBlank(lines[l + 1].content)
        let rep = prefix + block + (nextIsText ? eol : "")
        let caret = p + prefix.utf16.count + block.utf16.count
        return TextEdit(range: NSRange(location: p, length: 0), replacement: rep,
                             selection: NSRange(location: caret, length: 0))
    }

    // MARK: Table of contents

    /// Nested `- [Heading](#slug)` list from every heading (ATX and setext).
    /// GitHub-style slugs; duplicates get `-1`, `-2`. Rows joined by the text's line
    /// ending; no trailing newline.
    public static func tableOfContents(text: String) -> String {
        var headings: [(level: Int, title: String)] = []
        func walk(_ m: Markup) {
            if let h = m as? Heading { headings.append((h.level, inlineText(h))) }
            for c in m.children { walk(c) }
        }
        walk(Document(parsing: text, options: .disableSmartOpts))

        var used = Set<String>()
        var counts: [String: Int] = [:]
        var stack: [Int] = []
        var out: [String] = []
        for h in headings {
            let base = slug(h.title)
            var s = base
            while used.contains(s) {
                counts[base, default: 0] += 1
                s = "\(base)-\(counts[base]!)"
            }
            used.insert(s)
            while let top = stack.last, top >= h.level { stack.removeLast() }
            let depth = stack.count
            stack.append(h.level)
            let title = h.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            out.append(String(repeating: "  ", count: depth) + "- [\(title)](#\(s))")
        }
        return out.joined(separator: LineEnding.of(text))
    }

    /// Heading text without markup delimiters (code spans give their contents).
    private static func inlineText(_ m: Markup) -> String {
        if let t = m as? Text { return t.string }
        if let c = m as? InlineCode { return c.code }
        if m is SoftBreak || m is LineBreak { return " " }
        return m.children.map(inlineText).joined()
    }

    static func slug(_ title: String) -> String {
        var s = ""
        for c in title.lowercased() {
            if c == " " { s.append("-") }
            else if c.isLetter || c.isNumber || c == "-" || c == "_" { s.append(c) }
        }
        return s
    }
}
