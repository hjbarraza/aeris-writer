import Foundation

/// Rich text (the pasteboard's HTML) to Markdown: paragraphs, headings, bullet and
/// numbered lists with their nesting, pipe tables, links, bold, italic, code and quotes.
/// A small tolerant HTML reader plus a writer, not a Markdown parser. Output uses "\n";
/// the caller converts to the document's line ending (`LineEnding.convert`).
public enum RichTextMarkdown {
    /// The Markdown for `html`, or nil when it holds nothing worth converting (no list,
    /// table, link, heading, emphasis, code or quote): such a paste stays a plain paste.
    /// `emphasisCounts` false (the plain-Paste path): bold, italic and inline code alone are not
    /// structure, so code or prose from an editor that only colours and bolds pastes unchanged.
    /// HTML over `maxHTMLBytes` is not converted (nil).
    public static func convert(html: String, emphasisCounts: Bool = true) -> String? {
        guard html.utf8.count <= maxHTMLBytes else { return nil }
        var writer = Writer()
        writer.emphasisCounts = emphasisCounts
        let root = Parser.parse(html)
        let blocks = writer.blocks(root.children)
        guard writer.sawStructure else { return nil }
        let out = blocks.joined(separator: "\n\n")
        return out.isEmpty ? nil : out
    }

    public static let maxHTMLBytes = 2_000_000
    /// Elements nested deeper than this are not kept (their text joins the nearest kept ancestor),
    /// so every walk of the tree, and freeing it, has bounded depth.
    static let maxDepth = 256

    // MARK: Tree

    final class Node {
        let tag: String          // lowercase; "" for text
        var attrs: [String: String]
        var children: [Node] = []
        var text: String
        init(tag: String, attrs: [String: String] = [:], text: String = "") {
            self.tag = tag; self.attrs = attrs; self.text = text
        }
    }

    // MARK: Reading HTML

    enum Parser {
        static let void: Set<String> = ["br", "hr", "img", "meta", "link", "input", "col", "wbr", "area", "base"]
        static let skipped: Set<String> = ["script", "style", "head", "title", "template", "svg"]
        /// Tags whose open implies closing an open one of these (up to the stop tags).
        static let implied: [String: (closes: Set<String>, stops: Set<String>)] = [
            "li": (["li"], ["ul", "ol"]),
            "p": (["p"], ["div", "td", "th", "li", "blockquote", "table"]),
            "td": (["td", "th"], ["tr", "table"]), "th": (["td", "th"], ["tr", "table"]),
            "tr": (["tr", "td", "th"], ["table", "thead", "tbody", "tfoot"]),
            "thead": (["tbody", "thead", "tfoot", "tr", "td", "th"], ["table"]),
            "tbody": (["tbody", "thead", "tfoot", "tr", "td", "th"], ["table"]),
        ]

        static func parse(_ html: String) -> Node {
            let root = Node(tag: "#root")
            var stack = [root]
            let s = Array(html.unicodeScalars)
            var i = 0
            var skipUntil: String?
            var overflow: [String: Int] = [:]      // opened past maxDepth, not kept: their closes are ignored

            func addText(_ t: String) {
                guard !t.isEmpty else { return }
                stack.last!.children.append(Node(tag: "", text: decode(t)))
            }
            func close(_ name: String) {
                if let n = overflow[name], n > 0 { overflow[name] = n - 1; return }
                guard let at = stack.lastIndex(where: { $0.tag == name }), at > 0 else { return }
                stack.removeSubrange(at...)
            }

            while i < s.count {
                if s[i] != "<" {
                    var j = i
                    while j < s.count, s[j] != "<" { j += 1 }
                    if skipUntil == nil { addText(String(String.UnicodeScalarView(s[i..<j]))) }
                    i = j
                    continue
                }
                // Comment
                if s[i...].starts(with: "<!--".unicodeScalars) {
                    var j = i + 4
                    while j < s.count, !(s[j] == ">" && j >= i + 6 && s[j - 1] == "-" && s[j - 2] == "-") { j += 1 }
                    i = min(j + 1, s.count)
                    continue
                }
                // Tag
                var j = i + 1
                var quote: Unicode.Scalar?
                while j < s.count {
                    if let q = quote { if s[j] == q { quote = nil } }
                    else if s[j] == "\"" || s[j] == "'" { quote = s[j] }
                    else if s[j] == ">" { break }
                    j += 1
                }
                let body = String(String.UnicodeScalarView(s[(i + 1)..<min(j, s.count)]))
                i = min(j + 1, s.count)
                if body.hasPrefix("!") || body.hasPrefix("?") { continue }
                let closing = body.hasPrefix("/")
                let (name, attrs) = parseTag(closing ? String(body.dropFirst()) : body)
                guard !name.isEmpty else { continue }
                if let until = skipUntil {
                    if closing, name == until { skipUntil = nil }
                    continue
                }
                if closing { close(name); continue }
                if skipped.contains(name), !body.hasSuffix("/") { skipUntil = name; continue }
                if let rule = implied[name] {
                    var k = stack.count - 1
                    while k > 0, !rule.stops.contains(stack[k].tag) {
                        if rule.closes.contains(stack[k].tag) { stack.removeSubrange(k...); break }
                        k -= 1
                    }
                }
                let isVoid = void.contains(name) || body.hasSuffix("/")
                if !isVoid, stack.count > maxDepth { overflow[name, default: 0] += 1; continue }
                let node = Node(tag: name, attrs: attrs)
                stack.last!.children.append(node)
                if !isVoid { stack.append(node) }
            }
            return root
        }

        /// `a href="x" class=y` -> ("a", [href: x, class: y])
        static func parseTag(_ body: String) -> (String, [String: String]) {
            let s = Array(body.unicodeScalars)
            var i = 0
            func skipSpace() { while i < s.count, CharacterSet.whitespacesAndNewlines.contains(s[i]) { i += 1 } }
            skipSpace()
            var name = ""
            while i < s.count, !CharacterSet.whitespacesAndNewlines.contains(s[i]), s[i] != "/" {
                name.unicodeScalars.append(s[i]); i += 1
            }
            var attrs: [String: String] = [:]
            while i < s.count {
                skipSpace()
                var key = ""
                while i < s.count, !CharacterSet.whitespacesAndNewlines.contains(s[i]), s[i] != "=", s[i] != "/" {
                    key.unicodeScalars.append(s[i]); i += 1
                }
                if i < s.count, s[i] == "/" { i += 1; continue }
                skipSpace()
                var value = ""
                if i < s.count, s[i] == "=" {
                    i += 1; skipSpace()
                    if i < s.count, s[i] == "\"" || s[i] == "'" {
                        let q = s[i]; i += 1
                        while i < s.count, s[i] != q { value.unicodeScalars.append(s[i]); i += 1 }
                        i += 1
                    } else {
                        while i < s.count, !CharacterSet.whitespacesAndNewlines.contains(s[i]) {
                            value.unicodeScalars.append(s[i]); i += 1
                        }
                    }
                }
                if !key.isEmpty { attrs[key.lowercased()] = decode(value) }
            }
            return (name.lowercased(), attrs)
        }

        static let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
            "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "lsquo": "\u{2018}",
            "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{A9}",
            "bull": "\u{2022}", "middot": "\u{B7}", "times": "\u{D7}", "euro": "\u{20AC}",
        ]

        static func decode(_ t: String) -> String {
            guard t.contains("&") else { return t }
            var out = "", rest = Substring(t)
            while let amp = rest.firstIndex(of: "&") {
                out += rest[..<amp]
                let after = rest[rest.index(after: amp)...]
                if let semi = after.prefix(10).firstIndex(of: ";") {
                    let name = String(after[..<semi])
                    var value: String?
                    if name.hasPrefix("#") {
                        let digits = name.dropFirst()
                        let code = digits.first == "x" || digits.first == "X"
                            ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                        value = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                    } else {
                        value = named[name]
                    }
                    if let value { out += value; rest = after[after.index(after: semi)...]; continue }
                }
                out += "&"
                rest = after
            }
            return out + rest
        }
    }

    // MARK: Writing Markdown

    struct Writer {
        var sawStructure = false
        var emphasisCounts = true

        static let blockTags: Set<String> = [
            "p", "div", "section", "article", "header", "footer", "main", "nav", "aside", "figure", "figcaption",
            "body", "html", "form", "details", "summary", "address", "dl", "dt", "dd", "center",
            "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "blockquote", "pre", "hr",
        ]

        /// Block-level Markdown for `nodes`; loose inline runs between blocks become paragraphs.
        mutating func blocks(_ nodes: [Node]) -> [String] {
            var out: [String] = []
            var run = ""
            func flush() {
                let t = Writer.escapeLineStarts(Writer.tidy(run))
                if !t.isEmpty { out.append(t) }
                run = ""
            }
            for n in nodes {
                guard n.tag != "", Writer.blockTags.contains(n.tag) else { run += inline(n, State()); continue }
                flush()
                switch n.tag {
                case "ul", "ol":
                    sawStructure = true
                    let list = list(n, indent: "")
                    if !list.isEmpty { out.append(list) }
                case "table":
                    if let t = table(n) { sawStructure = true; out.append(t) }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    let text = Writer.tidy(inlineChildren(n, State())).replacingOccurrences(of: "\n", with: " ")
                    if !text.isEmpty {
                        sawStructure = true
                        out.append(String(repeating: "#", count: Int(String(n.tag.last!))!) + " " + text)
                    }
                case "blockquote":
                    let inner = blocks(n.children).joined(separator: "\n\n")
                    if !inner.isEmpty {
                        sawStructure = true
                        out.append(inner.split(separator: "\n", omittingEmptySubsequences: false)
                            .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n"))
                    }
                case "pre":
                    var code = text(of: n)
                    while code.hasSuffix("\n") { code.removeLast() }
                    if !code.isEmpty {
                        sawStructure = true
                        var longest = 0, current = 0
                        for c in code { current = c == "`" ? current + 1 : 0; longest = max(longest, current) }
                        let fence = String(repeating: "`", count: max(3, longest + 1))
                        out.append(fence + "\n" + code + "\n" + fence)
                    }
                case "hr":
                    sawStructure = true
                    out.append("---")
                default:                              // p, div, li strays, ...
                    out += blocks(n.children)
                }
            }
            flush()
            return out
        }

        /// A list as lines; `indent` is the nesting prefix. Bullets `- `, numbers from the start attribute.
        mutating func list(_ node: Node, indent: String) -> String {
            let ordered = node.tag == "ol"
            var number = Int(node.attrs["start"] ?? "") ?? 1
            var lines: [String] = []
            for child in node.children {
                if child.tag == "ul" || child.tag == "ol" {            // nested list sibling of the items
                    let nested = list(child, indent: indent + String(repeating: " ", count: lines.isEmpty ? 2 : lastMarkerWidth))
                    if !nested.isEmpty { lines.append(nested) }
                    continue
                }
                guard child.tag == "li" else { continue }
                let marker = ordered ? "\(number). " : "- "
                number += 1
                lastMarkerWidth = marker.count
                let nestedIndent = indent + String(repeating: " ", count: marker.count)
                var text = ""
                var nested: [String] = []
                for part in child.children {
                    if part.tag == "ul" || part.tag == "ol" {
                        nested.append(list(part, indent: nestedIndent))
                    } else if part.tag != "", Writer.blockTags.contains(part.tag) {
                        let t = blocks([part]).joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
                        text += (text.isEmpty || t.isEmpty ? "" : " ") + t
                    } else {
                        text += inline(part, State())
                    }
                }
                let item = Writer.tidy(text).replacingOccurrences(of: "\n", with: " ")
                lines.append(indent + marker + item)
                lines += nested.filter { !$0.isEmpty }
            }
            return lines.joined(separator: "\n")
        }
        private var lastMarkerWidth = 2

        /// A pipe table whose first row is the header; nil when there are no cells.
        mutating func table(_ node: Node) -> String? {
            var rows: [[String]] = []
            func collect(_ n: Node) {
                for c in n.children {
                    if c.tag == "tr" {
                        rows.append(c.children.filter { $0.tag == "td" || $0.tag == "th" }.map { cell in
                            Writer.tidy(inlineChildren(cell, State())).replacingOccurrences(of: "\n", with: " ")
                                .replacingOccurrences(of: "|", with: "\\|")
                        })
                    } else if ["thead", "tbody", "tfoot"].contains(c.tag) {
                        collect(c)
                    }
                }
            }
            collect(node)
            let width = rows.map(\.count).max() ?? 0
            guard width > 0 else { return nil }
            func line(_ cells: [String]) -> String {
                "| " + (cells + Array(repeating: "", count: width - cells.count)).joined(separator: " | ") + " |"
            }
            var out = [line(rows[0]), line(Array(repeating: "---", count: width))]
            out += rows.dropFirst().map(line)
            return out.joined(separator: "\n")
        }

        // MARK: Inline

        struct State { var bold = false, italic = false }

        mutating func inlineChildren(_ n: Node, _ st: State) -> String {
            n.children.map { inline($0, st) }.joined()
        }

        /// Inline Markdown; whitespace runs collapse to one space (lines are kept by `br`).
        mutating func inline(_ n: Node, _ st: State) -> String {
            if n.tag == "" {
                return Writer.escape(n.text.replacingOccurrences(of: "\u{A0}", with: " ")
                    .replacingOccurrences(of: "[ \t\r\n]+", with: " ", options: .regularExpression))
            }
            if Writer.blockTags.contains(n.tag) {          // a block inside inline content: its text, spaced
                let t = blocks([n]).joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
                return " " + t + " "
            }
            switch n.tag {
            case "br": return "\\\n"
            case "img", "input": return ""
            case "code", "kbd", "samp", "tt":
                let t = text(of: n).replacingOccurrences(of: "\n", with: " ")
                guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return t }
                if emphasisCounts { sawStructure = true }
                let fence = t.contains("`") ? "``" : "`"
                return fence + t.trimmingCharacters(in: .whitespaces) + fence
            case "a":
                let inner = inlineChildren(n, st)
                guard let href = n.attrs["href"], !href.isEmpty,
                      !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return inner }
                let scheme = href.trimmingCharacters(in: .whitespaces).lowercased().prefix { $0 != ":" && $0 != "/" }
                if ["javascript", "vbscript", "data"].contains(String(scheme)) { return inner }
                sawStructure = true
                let url = href.replacingOccurrences(of: " ", with: "%20")
                    .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                return wrap(inner, "[", "](\(url))")
            default: break
            }
            var st = st
            var bold = ["b", "strong"].contains(n.tag), italic = ["i", "em", "cite", "dfn"].contains(n.tag)
            let style = (n.attrs["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            if style.contains("font-weight:") {
                let w = style.components(separatedBy: "font-weight:")[1].prefix { $0 != ";" }
                bold = w == "bold" || w == "bolder" || (Int(w) ?? 0) >= 600
            }
            if style.contains("font-style:") {
                italic = style.components(separatedBy: "font-style:")[1].hasPrefix("italic")
            }
            let newBold = bold && !st.bold, newItalic = italic && !st.italic
            st.bold = st.bold || bold; st.italic = st.italic || italic
            var out = inlineChildren(n, st)
            if newItalic { out = wrap(out, "*", "*") }
            if newBold { out = wrap(out, "**", "**") }
            return out
        }

        /// `open` + trimmed text + `close`, keeping edge spaces outside the markers.
        mutating func wrap(_ s: String, _ open: String, _ close: String) -> String {
            let core = s.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return s }
            if open != "[", emphasisCounts { sawStructure = true }
            let lead = s.prefix { $0 == " " }, trail = String(s.reversed().prefix { $0 == " " })
            return lead + open + core + close + trail
        }

        /// Raw text of a node (code), no escaping, whitespace kept.
        func text(of n: Node) -> String {
            if n.tag == "" { return n.text.replacingOccurrences(of: "\u{A0}", with: " ") }
            if n.tag == "br" { return "\n" }
            return n.children.map(text(of:)).joined()
        }

        /// Backslash-escapes the characters that would turn text into Markdown.
        static func escape(_ s: String) -> String {
            var out = ""
            let chars = Array(s)
            for (i, c) in chars.enumerated() {
                switch c {
                case "\\", "*", "`", "[", "]", "<", ">": out += "\\" + String(c)
                case "&":
                    // "&lt;" typed as text must not become "<" when rendered.
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    out += next.isLetter || next == "#" ? "\\&" : "&"
                case "_":
                    // Inside a word (snake_case) an underscore is plain text.
                    let inWord = i > 0 && i + 1 < chars.count && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                        && (chars[i + 1].isLetter || chars[i + 1].isNumber)
                    out += inWord ? "_" : "\\_"
                default: out.append(c)
                }
            }
            return out
        }

        /// A paragraph line that starts like a heading, list item or quote gets a backslash.
        static func escapeLineStarts(_ s: String) -> String {
            s.replacingOccurrences(of: "(?m)^( {0,3})(#{1,6}(?=\\s|$)|[-+](?=\\s))", with: "$1\\\\$2", options: .regularExpression)
                .replacingOccurrences(of: "(?m)^( {0,3}\\d+)([.)])(?=\\s)", with: "$1\\\\$2", options: .regularExpression)
        }

        /// Collapses space runs (text nodes meet at edges), trims spaces around each line and the whole.
        static func tidy(_ s: String) -> String {
            s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression).split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
