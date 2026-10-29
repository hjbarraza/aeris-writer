import Foundation
import Markdown

/// One text replacement, in UTF-16 (`NSRange`) coordinates so it maps straight
/// onto `NSTextView`: replace `range` with `replacement`, then select `selection`
/// (post-edit coordinates).
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// `text` with this edit applied.
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

public enum InlineMarker: Sendable {
    case strong, emphasis, code, strikethrough, highlight, link, image, footnote, wikilink, comment
}

/// Pure range maths for the inline Format commands. Toggles wrap or unwrap the
/// selection; with a caret they act on the word under it, remove an empty pair,
/// or insert one.
public enum InlineEdit {
    public static func toggle(_ m: InlineMarker, in text: String, selection: NSRange) -> TextEdit {
        let s = text as NSString
        let loc = min(max(selection.location, 0), s.length)
        let sel = NSRange(location: loc, length: min(max(selection.length, 0), s.length - loc))
        switch m {
        case .link: return unwrapLink(text, sel, image: false) ?? link(s, sel, prefix: "[")
        case .image: return unwrapLink(text, sel, image: true) ?? link(s, sel, prefix: "![")
        case .footnote: return footnote(s, sel)
        default: return pair(m, s, sel)
        }
    }

    /// (open, close) spellings; the first is what we write, the rest we also unwrap.
    private static func pairs(_ m: InlineMarker) -> [(String, String)] {
        switch m {
        case .strong: return [("**", "**"), ("__", "__")]
        case .emphasis: return [("_", "_"), ("*", "*")]
        case .code: return [("`", "`")]
        case .strikethrough: return [("~~", "~~")]
        case .highlight: return [("==", "==")]
        case .wikilink: return [("[[", "]]")]
        case .comment: return [("<!-- ", " -->"), ("<!--", "-->")]
        case .link, .image, .footnote: return []
        }
    }

    private static func pair(_ m: InlineMarker, _ s: NSString, _ sel: NSRange) -> TextEdit {
        if sel.length > 0 { return toggleRange(m, s, sel) }
        let p = sel.location
        for (o, c) in pairs(m) where wrapped(s, o, c, sel) {
            let start = p - o.utf16.count
            return TextEdit(range: NSRange(location: start, length: o.utf16.count + c.utf16.count),
                            replacement: "", selection: NSRange(location: start, length: 0))
        }
        if let w = wordRange(s, p) {
            let e = toggleRange(m, s, w)
            return TextEdit(range: e.range, replacement: e.replacement,
                            selection: NSRange(location: e.selection.location + p - w.location, length: 0))
        }
        let (o, c) = pairs(m)[0]
        return TextEdit(range: sel, replacement: o + c, selection: NSRange(location: p + o.utf16.count, length: 0))
    }

    private static func toggleRange(_ m: InlineMarker, _ s: NSString, _ r: NSRange) -> TextEdit {
        if m == .code { return toggleCode(s, r) }
        let inner = s.substring(with: r)
        for (o, c) in pairs(m) {
            let ol = o.utf16.count, cl = c.utf16.count
            // Selection includes the markers.
            if r.length >= ol + cl, has(s, o, at: r.location), has(s, c, at: NSMaxRange(r) - cl) {
                let body = NSRange(location: r.location + ol, length: r.length - ol - cl)
                let single = ol == 1 && o == c
                if !single || (body.length > 0 && !has(s, o, at: body.location) && !has(s, c, at: NSMaxRange(body) - 1)) {
                    return TextEdit(range: r, replacement: s.substring(with: body),
                                    selection: NSRange(location: r.location, length: body.length))
                }
            }
            // Markers just outside the selection.
            if wrapped(s, o, c, r) {
                return TextEdit(range: NSRange(location: r.location - ol, length: r.length + ol + cl),
                                replacement: inner, selection: NSRange(location: r.location - ol, length: r.length))
            }
        }
        let (o, c) = pairs(m)[0]
        return TextEdit(range: r, replacement: o + inner + c,
                        selection: NSRange(location: r.location + o.utf16.count, length: r.length))
    }

    /// `o` ends at `r.location` and `c` starts at `NSMaxRange(r)`. A single-char
    /// marker must not be part of a longer run, so `**x**` is not `*` emphasis.
    private static func wrapped(_ s: NSString, _ o: String, _ c: String, _ r: NSRange) -> Bool {
        let ol = o.utf16.count, end = NSMaxRange(r)
        guard has(s, o, at: r.location - ol), has(s, c, at: end) else { return false }
        if ol == 1 && o == c { return !has(s, o, at: r.location - 2) && !has(s, c, at: end + 1) }
        return true
    }

    /// Inline code: CommonMark backtick runs. Unwraps `` `x` `` / ``` `` a`b `` ```
    /// (inclusive or outside); wraps with a run longer than any inside, space-padded.
    private static func toggleCode(_ s: NSString, _ r: NSRange) -> TextEdit {
        let inner = s.substring(with: r)
        let lead = ticks(s, from: r.location, step: 1), trail = ticks(s, from: NSMaxRange(r) - 1, step: -1)
        if lead > 0, lead == trail, r.length > 2 * lead {
            var body = NSRange(location: r.location + lead, length: r.length - 2 * lead)
            if body.length >= 2, has(s, " ", at: body.location), has(s, " ", at: NSMaxRange(body) - 1),
               !s.substring(with: body).allSatisfy({ $0 == " " }) {
                body = NSRange(location: body.location + 1, length: body.length - 2)
            }
            return TextEdit(range: r, replacement: s.substring(with: body),
                            selection: NSRange(location: r.location, length: body.length))
        }
        var a = r.location, b = NSMaxRange(r)
        if has(s, " ", at: a - 1), has(s, " ", at: b),
           ticks(s, from: a - 2, step: -1) > 0, ticks(s, from: a - 2, step: -1) == ticks(s, from: b + 1, step: 1) {
            a -= 1; b += 1
        }
        let before = ticks(s, from: a - 1, step: -1), after = ticks(s, from: b, step: 1)
        if before > 0, before == after {
            return TextEdit(range: NSRange(location: a - before, length: b + after - (a - before)),
                            replacement: inner, selection: NSRange(location: a - before, length: r.length))
        }
        var longest = 0, run = 0
        for u in inner.utf16 { run = u == 0x60 ? run + 1 : 0; longest = max(longest, run) }
        let fence = String(repeating: "`", count: longest + 1), pad = longest > 0 ? " " : ""
        return TextEdit(range: r, replacement: fence + pad + inner + pad + fence,
                        selection: NSRange(location: r.location + longest + 1 + pad.utf16.count, length: r.length))
    }

    /// Length of the backtick run starting at `i` going in direction `step`.
    private static func ticks(_ s: NSString, from i: Int, step: Int) -> Int {
        var n = 0, j = i
        while j >= 0, j < s.length, s.character(at: j) == 0x60 { n += 1; j += step }
        return n
    }

    /// The innermost link (image) holding the selection or caret, replaced by its
    /// text (alt text), selected. Bare autolinks have no markers and don't count.
    private static func unwrapLink(_ text: String, _ sel: NSRange, image: Bool) -> TextEdit? {
        let conv = SpanCollector(text)
        var found: TextEdit?
        func walk(_ m: Markup) {
            if image ? m is Image : m is Link, let r = conv.nsRange(m.range) {
                let inside = sel.length == 0
                    ? r.location < sel.location && sel.location < NSMaxRange(r)
                    : r.location <= sel.location && NSMaxRange(sel) <= NSMaxRange(r)
                let kids = m.children.compactMap { conv.nsRange($0.range) }
                let body = kids.first.map { NSRange(location: $0.location, length: NSMaxRange(kids.last!) - $0.location) }
                    ?? NSRange(location: r.location, length: 0)
                if inside, body != r {
                    found = TextEdit(range: r, replacement: (text as NSString).substring(with: body),
                                     selection: NSRange(location: r.location, length: body.length))
                }
            }
            m.children.forEach(walk)
        }
        walk(MarkdownCore.parse(text))
        return found
    }

    /// `[sel](|)`, or `[|](sel)` when the selection is a URL; empty → `[|]()`.
    private static func link(_ s: NSString, _ sel: NSRange, prefix: String) -> TextEdit {
        let t = s.substring(with: sel), pl = prefix.utf16.count
        let isURL = (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(where: \.isWhitespace)
        if isURL {
            return TextEdit(range: sel, replacement: prefix + "](" + t + ")",
                            selection: NSRange(location: sel.location + pl, length: 0))
        }
        let caret = sel.location + pl + (sel.length == 0 ? 0 : sel.length + 2)
        return TextEdit(range: sel, replacement: prefix + t + "]()", selection: NSRange(location: caret, length: 0))
    }

    /// Inserts `[^n]` after the selection and appends `[^n]: ` as the last
    /// paragraph; one edit spanning from the insertion point to the end.
    private static func footnote(_ s: NSString, _ sel: NSRange) -> TextEdit {
        let re = try! NSRegularExpression(pattern: #"\[\^(\d+)\]"#)
        let used = re.matches(in: s as String, range: NSRange(location: 0, length: s.length))
            .compactMap { Int(s.substring(with: $0.range(at: 1))) }
        let label = "[^\((used.max() ?? 0) + 1)]"
        let p = NSMaxRange(sel)
        var end = s.length
        while end > p, has(s, "\n", at: end - 1) || has(s, "\r", at: end - 1) { end -= 1 }
        let replacement = label + s.substring(with: NSRange(location: p, length: end - p)) + String(repeating: LineEnding.of(s as String), count: 2) + label + ": "
        return TextEdit(range: NSRange(location: p, length: s.length - p), replacement: replacement,
                        selection: NSRange(location: p + replacement.utf16.count, length: 0))
    }

    /// The run of letters/digits around `p`, if the caret touches one.
    private static func wordRange(_ s: NSString, _ p: Int) -> NSRange? {
        func isWord(_ r: NSRange) -> Bool {
            s.substring(with: r).unicodeScalars.first.map { CharacterSet.alphanumerics.contains($0) } ?? false
        }
        var start = p, end = p
        while start > 0 {
            let r = s.rangeOfComposedCharacterSequence(at: start - 1)
            guard isWord(r) else { break }
            start = r.location
        }
        while end < s.length {
            let r = s.rangeOfComposedCharacterSequence(at: end)
            guard isWord(r) else { break }
            end = NSMaxRange(r)
        }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    private static func has(_ s: NSString, _ str: String, at i: Int) -> Bool {
        let n = str.utf16.count
        return i >= 0 && i + n <= s.length && s.substring(with: NSRange(location: i, length: n)) == str
    }
}

// MARK: Clear formatting

extension InlineEdit {
    /// Removes inline markers from the selection (or the caret's line): strong,
    /// emphasis, code, strikethrough and links/images (→ their text / alt text) by
    /// swift-markdown positions; `==highlight==` and `[[wikilinks]]`, which CommonMark
    /// doesn't parse, by scanning the source outside code, HTML and link destinations.
    /// A node touching the selection loses both its markers. Block syntax is untouched.
    public static func clearStyles(in text: String, selection: NSRange) -> TextEdit {
        let s = text as NSString
        let loc = min(max(selection.location, 0), s.length)
        let sel = NSRange(location: loc, length: min(max(selection.length, 0), s.length - loc))
        let target = sel.length > 0 ? sel : s.lineRange(for: sel)
        func touches(_ r: NSRange) -> Bool { r.location < NSMaxRange(target) && target.location < NSMaxRange(r) }
        let conv = SpanCollector(text)
        var cuts: [NSRange] = [], opaque: [NSRange] = []

        func walk(_ m: Markup) {
            if let r = conv.nsRange(m.range) {
                switch m {
                case is Strong, is Emphasis, is Strikethrough, is Link, is Image:
                    let kids = m.children.compactMap { conv.nsRange($0.range) }
                    let lead = NSRange(location: r.location, length: (kids.first?.location ?? NSMaxRange(r)) - r.location)
                    let tail = kids.last.map { NSRange(location: NSMaxRange($0), length: NSMaxRange(r) - NSMaxRange($0)) }
                    opaque += [lead, tail].compactMap { $0 }
                    if touches(r) { cuts += [lead, tail].compactMap { $0 } }
                case is InlineCode:
                    opaque.append(r)
                    if touches(r) { cuts += codeFences(s, r) }
                case is CodeBlock, is HTMLBlock, is InlineHTML:
                    opaque.append(r)
                default: break
                }
            }
            m.children.forEach(walk)
        }
        walk(MarkdownCore.parse(text))

        // `==x==` and `[[x]]`: both markers on one line, outside opaque ranges.
        let lines = s.lineRange(for: target)
        func isOpaque(_ r: NSRange) -> Bool { opaque.contains { NSIntersectionRange($0, r).length > 0 } }
        for (open, close) in [("==", "=="), ("[[", "]]")] {
            var i = lines.location
            while i < NSMaxRange(lines) {
                let o = s.range(of: open, range: NSRange(location: i, length: NSMaxRange(lines) - i))
                guard o.location != NSNotFound else { break }
                let lineEnd = NSMaxRange(s.lineRange(for: o))
                let from = NSMaxRange(o) + 1
                let c = from < lineEnd ? s.range(of: close, range: NSRange(location: from, length: lineEnd - from))
                                       : NSRange(location: NSNotFound, length: 0)
                guard !isOpaque(o), c.location != NSNotFound, !isOpaque(c) else { i = o.location + 1; continue }
                if touches(NSUnionRange(o, c)) { cuts += [o, c] }
                i = NSMaxRange(c)
            }
        }

        var merged: [NSRange] = []
        for c in cuts.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location })
        where merged.last.map({ NSMaxRange($0) <= c.location }) ?? true {
            merged.append(c)
        }
        guard let first = merged.first, let last = merged.last else {
            return TextEdit(range: sel, replacement: s.substring(with: sel), selection: sel)
        }
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var out = "", p = span.location
        for c in merged {
            out += s.substring(with: NSRange(location: p, length: c.location - p))
            p = NSMaxRange(c)
        }
        out += s.substring(with: NSRange(location: p, length: NSMaxRange(span) - p))
        // A position moves left by the cut characters before it.
        func map(_ x: Int) -> Int {
            x - merged.reduce(0) { $0 + max(0, min(NSMaxRange($1), x) - $1.location) }
        }
        let a = map(sel.location), b = map(NSMaxRange(sel))
        return TextEdit(range: span, replacement: out, selection: NSRange(location: a, length: b - a))
    }

    /// The backtick runs of a code span, plus one padding space each side when both
    /// sides have one (CommonMark strips that pair).
    private static func codeFences(_ s: NSString, _ r: NSRange) -> [NSRange] {
        let n = ticks(s, from: r.location, step: 1)
        guard n > 0, r.length >= 2 * n else { return [] }
        let body = NSRange(location: r.location + n, length: r.length - 2 * n)
        let pad = body.length >= 2 && has(s, " ", at: body.location) && has(s, " ", at: NSMaxRange(body) - 1)
            && !s.substring(with: body).allSatisfy({ $0 == " " }) ? 1 : 0
        return [NSRange(location: r.location, length: n + pad), NSRange(location: NSMaxRange(r) - n - pad, length: n + pad)]
    }
}

extension SpanCollector {
    /// UTF-16 range of a swift-markdown source range.
    func nsRange(_ r: SourceRange?) -> NSRange? {
        guard let r else { return nil }
        let a = utf16Offset(r.lowerBound)
        return NSRange(location: a, length: utf16Offset(r.upperBound) - a)
    }
}
