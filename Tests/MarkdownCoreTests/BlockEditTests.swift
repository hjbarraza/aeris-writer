import Testing
import Foundation
@testable import MarkdownCore

// Mirrors Sources/mdcheck/BlockEditChecks.swift (same cases).
struct BlockEditTests {
    @Test func blockEdits() {
        func ap(_ text: String, _ e: TextEdit) -> String {
            (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        }
        func r(_ a: Int, _ b: Int = 0) -> NSRange { NSRange(location: a, length: b) }

        // Headings
        var e = BlockEdit.heading(2, text: "Hello", selection: r(0))
        #expect(ap("Hello", e) == "## Hello" && e.selection == r(3), "heading: add level, caret follows")
        #expect(ap("## Hello", BlockEdit.heading(2, text: "## Hello", selection: r(8))) == "Hello", "heading: same level removes")
        #expect(ap("## Hello", BlockEdit.heading(3, text: "## Hello", selection: r(2))) == "### Hello", "heading: replaces level")
        #expect(ap("## Hello", BlockEdit.heading(0, text: "## Hello", selection: r(0))) == "Hello", "heading: level 0 removes")
        e = BlockEdit.heading(1, text: "a\nb\nc", selection: r(0, 5))
        #expect(ap("a\nb\nc", e) == "# a\n# b\n# c" && e.selection == r(0, 11), "heading: multi-line")
        e = BlockEdit.heading(1, text: "a\nb", selection: r(3))
        #expect(ap("a\nb", e) == "a\n# b" && e.selection == r(5), "heading: caret on last line")
        #expect(ap("a\nb", BlockEdit.heading(1, text: "a\nb", selection: r(0, 2))) == "# a\nb", "heading: selection ending at line start skips that line")
        #expect(ap("a\r\nb", BlockEdit.heading(2, text: "a\r\nb", selection: r(0, 4))) == "## a\r\n## b", "heading: CRLF kept")
        #expect(ap("café ☕", BlockEdit.heading(1, text: "café ☕", selection: r(0))) == "# café ☕", "heading: non-ASCII")
        e = BlockEdit.heading(1, text: "😀 x", selection: r(4))
        #expect(ap("😀 x", e) == "# 😀 x" && e.selection == r(6), "heading: astral chars, UTF-16 caret")
        e = BlockEdit.heading(1, text: "", selection: r(0))
        #expect(ap("", e) == "# " && e.selection == r(2), "heading: empty document")
        #expect(ap("a\n\nb", BlockEdit.heading(1, text: "a\n\nb", selection: r(0, 4))) == "# a\n\n# b", "heading: blank lines skipped in multi-line")

        // Quote
        #expect(ap("a", BlockEdit.quote(text: "a", selection: r(0))) == "> a", "quote: add")
        #expect(ap("> a", BlockEdit.quote(text: "> a", selection: r(1))) == "a", "quote: toggle off")
        #expect(ap("a\n\nb", BlockEdit.quote(text: "a\n\nb", selection: r(0, 4))) == "> a\n>\n> b", "quote: multi-line with blank")
        #expect(ap("> a\n>\n> b", BlockEdit.quote(text: "> a\n>\n> b", selection: r(0, 9))) == "a\n\nb", "quote: multi-line toggle off")
        #expect(ap("> a\nb", BlockEdit.quote(text: "> a\nb", selection: r(0, 5))) == "> > a\n> b", "quote: mixed adds a level")
        #expect(ap("", BlockEdit.quote(text: "", selection: r(0))) == "> ", "quote: empty document")
        #expect(ap("a\r\nb", BlockEdit.quote(text: "a\r\nb", selection: r(0, 4))) == "> a\r\n> b", "quote: CRLF")
        #expect(ap("é", BlockEdit.quote(text: "é", selection: r(1))) == "> é", "quote: non-ASCII")

        // Code fence and display math
        e = BlockEdit.codeFence(text: "x", selection: r(0))
        #expect(ap("x", e) == "```\nx\n```" && e.selection == r(4), "fence: wrap line")
        #expect(ap("```\nx\n```", BlockEdit.codeFence(text: "```\nx\n```", selection: r(0, 9))) == "x", "fence: unwrap")
        e = BlockEdit.codeFence(text: "", selection: r(0))
        #expect(ap("", e) == "```\n\n```" && e.selection == r(4), "fence: empty document, caret inside")
        #expect(ap("a\nb\nc", BlockEdit.codeFence(text: "a\nb\nc", selection: r(2, 1))) == "a\n```\nb\n```\nc", "fence: middle line only")
        #expect(ap("a\r\nb", BlockEdit.codeFence(text: "a\r\nb", selection: r(0, 4))) == "```\r\na\r\nb\r\n```", "fence: CRLF")
        #expect(ap("日本", BlockEdit.codeFence(text: "日本", selection: r(2))) == "```\n日本\n```", "fence: non-ASCII")
        #expect(ap("x", BlockEdit.displayMath(text: "x", selection: r(1))) == "$$\nx\n$$", "math: wrap")
        #expect(ap("$$\nx\n$$", BlockEdit.displayMath(text: "$$\nx\n$$", selection: r(0, 7))) == "x", "math: unwrap")
        #expect(ap("", BlockEdit.displayMath(text: "", selection: r(0))) == "$$\n\n$$", "math: empty document")

        // Horizontal rule and page break
        e = BlockEdit.horizontalRule(text: "para", selection: r(2))
        #expect(ap("para", e) == "para\n\n---" && e.selection == r(9), "hr: after paragraph, blank line before")
        #expect(ap("", BlockEdit.horizontalRule(text: "", selection: r(0))) == "---", "hr: empty document")
        #expect(ap("a\n\nb", BlockEdit.horizontalRule(text: "a\n\nb", selection: r(2))) == "a\n\n---\n\nb", "hr: on blank line between paragraphs")
        #expect(ap("a\nb", BlockEdit.horizontalRule(text: "a\nb", selection: r(0))) == "a\n\n---\n\nb", "hr: caret on first line")
        #expect(ap("a\r\nb", BlockEdit.horizontalRule(text: "a\r\nb", selection: r(3))) == "a\r\nb\r\n\r\n---", "hr: CRLF, last line")
        #expect(ap("é", BlockEdit.pageBreak(text: "é", selection: r(1)))
              == "é\n\n<div style=\"page-break-after: always\"></div>", "page break: non-ASCII")
        #expect(ap("", BlockEdit.pageBreak(text: "", selection: r(0))) == "<div style=\"page-break-after: always\"></div>", "page break: empty document")

        // Callout
        e = BlockEdit.callout(kind: "NOTE", text: "hi", selection: r(0))
        #expect(ap("hi", e) == "> [!NOTE]\n> hi" && e.selection == r(14), "callout: wrap line")
        #expect(ap("", BlockEdit.callout(kind: "TIP", text: "", selection: r(0))) == "> [!TIP]\n> ", "callout: empty document")
        #expect(ap("a\n\nb", BlockEdit.callout(kind: "WARNING", text: "a\n\nb", selection: r(0, 4))) == "> [!WARNING]\n> a\n>\n> b", "callout: multi-line")
        #expect(ap("> [!NOTE]\n> a", BlockEdit.callout(kind: "TIP", text: "> [!NOTE]\n> a", selection: r(3))) == "> [!TIP]\n> a", "callout: change kind")
        #expect(ap("a\r\nb", BlockEdit.callout(kind: "NOTE", text: "a\r\nb", selection: r(0, 4))) == "> [!NOTE]\r\n> a\r\n> b", "callout: CRLF")

        // Table of contents
        #expect(BlockEdit.tableOfContents(text: "") == "", "toc: empty document")
        #expect(BlockEdit.tableOfContents(text: "no headings here") == "", "toc: no headings")
        #expect(BlockEdit.tableOfContents(text: "# A\n## B\n### C\n## B\nSetext\n---\n# Hello, World! 🎉")
              == "- [A](#a)\n  - [B](#b)\n    - [C](#c)\n  - [B](#b-1)\n  - [Setext](#setext)\n- [Hello, World! 🎉](#hello-world-)", "toc: nesting, duplicates, setext, punctuation, emoji")
        #expect(BlockEdit.tableOfContents(text: "# x\n# x\n# x") == "- [x](#x)\n- [x](#x-1)\n- [x](#x-2)", "toc: triple duplicate")
        #expect(BlockEdit.tableOfContents(text: "# Café Ünï\n") == "- [Café Ünï](#café-ünï)", "toc: non-ASCII slug")
        #expect(BlockEdit.tableOfContents(text: "### Deep\n# Top\r\n## Mid") == "- [Deep](#deep)\n- [Top](#top)\n  - [Mid](#mid)", "toc: skipped levels and CRLF")
        #expect(BlockEdit.tableOfContents(text: "# `code` and *em*") == "- [code and em](#code-and-em)", "toc: inline markup flattened")
        #expect(BlockEdit.tableOfContents(text: "```\n# not a heading\n```") == "", "toc: fenced code ignored")

        // Lists: toggle
        e = ListEdit.toggleList(.bullet, text: "a", selection: r(1))
        #expect(ap("a", e) == "- a" && e.selection == r(3), "list: bullet add")
        #expect(ap("- a", ListEdit.toggleList(.bullet, text: "- a", selection: r(3))) == "a", "list: bullet toggle off")
        #expect(ap("a\nb\nc", ListEdit.toggleList(.ordered, text: "a\nb\nc", selection: r(0, 5))) == "1. a\n2. b\n3. c", "list: ordered numbering")
        #expect(ap("a\n\nb", ListEdit.toggleList(.ordered, text: "a\n\nb", selection: r(0, 4))) == "1. a\n\n2. b", "list: ordered skips blank lines")
        #expect(ap("- a\n- b", ListEdit.toggleList(.ordered, text: "- a\n- b", selection: r(0, 7))) == "1. a\n2. b", "list: bullet to ordered")
        #expect(ap("1. a\n2. b", ListEdit.toggleList(.ordered, text: "1. a\n2. b", selection: r(0, 9))) == "a\nb", "list: ordered toggle off")
        #expect(ap("a", ListEdit.toggleList(.task, text: "a", selection: r(0))) == "- [ ] a", "list: task add")
        #expect(ap("- [x] a", ListEdit.toggleList(.task, text: "- [x] a", selection: r(0))) == "a", "list: task toggle off")
        #expect(ap("- [x] a", ListEdit.toggleList(.bullet, text: "- [x] a", selection: r(0))) == "- a", "list: task to bullet")
        #expect(ap("- [x] a", ListEdit.toggleList(.orderedTask, text: "- [x] a", selection: r(0))) == "1. [x] a", "list: task to ordered task keeps state")
        #expect(ap("a", ListEdit.toggleList(.orderedTask, text: "a", selection: r(0))) == "1. [ ] a", "list: ordered task add")
        #expect(ap("* a", ListEdit.toggleList(.task, text: "* a", selection: r(0))) == "* [ ] a", "list: keeps bullet char")
        #expect(ap("a\nb", ListEdit.toggleList(.bullet, text: "a\nb", selection: r(2))) == "a\n- b", "list: caret on last line")
        #expect(ap("", ListEdit.toggleList(.bullet, text: "", selection: r(0))) == "- ", "list: empty document")
        #expect(ap("a\r\nb", ListEdit.toggleList(.ordered, text: "a\r\nb", selection: r(0, 4))) == "1. a\r\n2. b", "list: CRLF")
        #expect(ap("été", ListEdit.toggleList(.bullet, text: "été", selection: r(3))) == "- été", "list: non-ASCII")
        #expect(ap("  a", ListEdit.toggleList(.bullet, text: "  a", selection: r(3))) == "  - a", "list: keeps indentation")

        // Lists: Return
        e = ListEdit.newline(text: "- a", selection: r(3))!
        #expect(ap("- a", e) == "- a\n- " && e.selection == r(6), "newline: bullet continues")
        #expect(ap("1. a", ListEdit.newline(text: "1. a", selection: r(4))!) == "1. a\n2. ", "newline: ordered increments")
        #expect(ap("1) a", ListEdit.newline(text: "1) a", selection: r(4))!) == "1) a\n2) ", "newline: ordered paren delimiter")
        #expect(ap("- [x] a", ListEdit.newline(text: "- [x] a", selection: r(7))!) == "- [x] a\n- [ ] ", "newline: task is new unchecked")
        #expect(ap("  * a", ListEdit.newline(text: "  * a", selection: r(5))!) == "  * a\n  * ", "newline: keeps indent and marker char")
        #expect(ap("+ a", ListEdit.newline(text: "+ a", selection: r(3))!) == "+ a\n+ ", "newline: plus marker")
        #expect(ap("- ab", ListEdit.newline(text: "- ab", selection: r(3))!) == "- a\n- b", "newline: splits item at caret")
        e = ListEdit.newline(text: "- ", selection: r(2))!
        #expect(ap("- ", e) == "" && e.selection == r(0), "newline: empty item ends list (first line)")
        e = ListEdit.newline(text: "a\n- b\n- ", selection: r(8))!
        #expect(ap("a\n- b\n- ", e) == "a\n- b\n" && e.selection == r(6), "newline: empty item ends list (last line)")
        #expect(ap("- [ ] ", ListEdit.newline(text: "- [ ] ", selection: r(6))!) == "", "newline: empty task ends list")
        #expect(ap("> q", ListEdit.newline(text: "> q", selection: r(3))!) == "> q\n> ", "newline: quote continues")
        #expect(ap("> ", ListEdit.newline(text: "> ", selection: r(2))!) == "", "newline: empty quote line ends quote")
        #expect(ListEdit.newline(text: "abc", selection: r(3)) == nil, "newline: plain text is nil")
        #expect(ListEdit.newline(text: "", selection: r(0)) == nil, "newline: empty document is nil")
        #expect(ListEdit.newline(text: "- a", selection: r(1)) == nil, "newline: caret inside marker is nil")
        #expect(ListEdit.newline(text: "- a", selection: r(0, 3)) == nil, "newline: non-empty selection is nil")
        #expect(ap("- a\r\n- b", ListEdit.newline(text: "- a\r\n- b", selection: r(3))!) == "- a\r\n- \r\n- b", "newline: CRLF")
        #expect(ap("- café", ListEdit.newline(text: "- café", selection: r(6))!) == "- café\n- ", "newline: non-ASCII")
        #expect(ListEdit.newline(text: "Title\n-", selection: r(7)) == nil, "newline: setext underline is not an item")
        #expect(!ListEdit.isItem(text: "Title\n-", selection: r(7)), "isItem: setext underline is not an item")
        #expect(ap("a\n\n-", ListEdit.newline(text: "a\n\n-", selection: r(4))!) == "a\n\n", "newline: lone - after a blank line is an empty item")
        #expect(ap("- a\n-", ListEdit.newline(text: "- a\n-", selection: r(5))!) == "- a\n", "newline: lone - under an item is an empty item")
        #expect(ap("- a\n  continuation\n-", ListEdit.newline(text: "- a\n  continuation\n-", selection: r(20))!) == "- a\n  continuation\n", "newline: lone - after an item's continuation line is an empty item")
        #expect(ListEdit.newline(text: "- a\n\nTitle\n-", selection: r(12)) == nil, "newline: setext underline after a list and a blank line")
        #expect(ap("x\r\ny\r\n- a", ListEdit.newline(text: "x\r\ny\r\n- a", selection: r(9))!) == "x\r\ny\r\n- a\r\n- ", "newline: document line ending from an earlier line")

        // Lists: ordered renumbering (M1.5-23)
        e = ListEdit.newline(text: "1. a\n2. b\n3. c", selection: r(4))!
        #expect(ap("1. a\n2. b\n3. c", e) == "1. a\n2. \n3. b\n4. c" && e.selection == r(8), "renumber: Return mid-list renumbers the items below")
        #expect(ap("1. a\n2. b", ListEdit.newline(text: "1. a\n2. b", selection: r(3))!) == "1. \n2. a\n3. b", "renumber: Return splitting an item")
        #expect(ap("1) a\n2) b", ListEdit.newline(text: "1) a\n2) b", selection: r(4))!) == "1) a\n2) \n3) b", "renumber: paren delimiter")
        #expect(ap("1. a\n\n2. b", ListEdit.newline(text: "1. a\n\n2. b", selection: r(4))!) == "1. a\n2. \n\n3. b", "renumber: across a blank line (loose list)")
        #expect(ap("1. a\n   1. x\n2. b", ListEdit.newline(text: "1. a\n   1. x\n2. b", selection: r(4))!) == "1. a\n2. \n   1. x\n3. b", "renumber: nested items left alone")
        #expect(ap("1. a\n2. b\n\npara\n\n3. c", ListEdit.newline(text: "1. a\n2. b\n\npara\n\n3. c", selection: r(4))!) == "1. a\n2. \n3. b\n\npara\n\n3. c", "renumber: stops at the end of the list")
        #expect(ap("1. a\n2. b\n- c\n3. d", ListEdit.newline(text: "1. a\n2. b\n- c\n3. d", selection: r(4))!) == "1. a\n2. \n3. b\n- c\n3. d", "renumber: stops at a bullet item")
        #expect(ap("1. a\n2. \n3. b", ListEdit.newline(text: "1. a\n2. \n3. b", selection: r(8))!) == "1. a\n\n2. b", "renumber: Return on an empty item clears it and renumbers")
        #expect(ap("1. a\r\n2. b", ListEdit.newline(text: "1. a\r\n2. b", selection: r(4))!) == "1. a\r\n2. \r\n3. b", "renumber: CRLF")
        e = ListEdit.delete(text: "1. a\n2. \n3. b\n4. c", range: r(5, 4))!
        #expect(ap("1. a\n2. \n3. b\n4. c", e) == "1. a\n2. b\n3. c" && e.selection == r(5), "renumber: deleting an item's line renumbers the items below")
        #expect(ap("1. a\n2. b\n3. c", ListEdit.delete(text: "1. a\n2. b\n3. c", range: r(4, 1))!) == "1. a2. b\n2. c", "renumber: joining two items renumbers")
        #expect(ap("1. a\n2. b\n3. c\n4. d", ListEdit.delete(text: "1. a\n2. b\n3. c\n4. d", range: r(4, 10))!) == "1. a\n2. d", "renumber: deleting across items")
        #expect(ListEdit.delete(text: "1. a\n2. b\n3. c", range: r(4, 0)) == nil, "renumber: empty deletion is nil")
        #expect(ListEdit.delete(text: "1. ab\n2. c", range: r(4, 1)) == nil, "renumber: deletion without a line break is nil")
        #expect(ListEdit.delete(text: "- a\n- b\n- c", range: r(3, 4)) == nil, "renumber: bullet list is nil")
        #expect(ListEdit.delete(text: "1. a\n2. b\n3. c", range: r(9, 5)) == nil, "renumber: deleting the last item needs no renumbering")

        // Lists: indent / outdent
        e = ListEdit.indent(text: "- a", selection: r(3))
        #expect(ap("- a", e) == "  - a" && e.selection == r(5), "indent: bullet by 2")
        #expect(ap("1. a", ListEdit.indent(text: "1. a", selection: r(0))) == "   1. a", "indent: ordered by 3")
        #expect(ap("a", ListEdit.indent(text: "a", selection: r(1))) == "    a", "indent: plain by 4")
        #expect(ap("- a\n\nb", ListEdit.indent(text: "- a\n\nb", selection: r(0, 6))) == "  - a\n\n    b", "indent: multi-line mixed, blank skipped")
        #expect(ap("", ListEdit.indent(text: "", selection: r(0))) == "    ", "indent: empty document")
        #expect(ap("  - a", ListEdit.outdent(text: "  - a", selection: r(5))) == "- a", "outdent: bullet")
        #expect(ap("      x", ListEdit.outdent(text: "      x", selection: r(7))) == "  x", "outdent: plain up to 4")
        #expect(ap("\tx", ListEdit.outdent(text: "\tx", selection: r(0))) == "x", "outdent: tab")
        #expect(ap("x", ListEdit.outdent(text: "x", selection: r(0))) == "x", "outdent: nothing to remove")
        #expect(ap("  - a\r\n  - b", ListEdit.outdent(text: "  - a\r\n  - b", selection: r(0, 11))) == "- a\r\n- b", "outdent: CRLF multi-line")
        #expect(ap("  - é", ListEdit.indent(text: "  - é", selection: r(5))) == "    - é", "indent: non-ASCII")
        e = ListEdit.outdent(text: "1. a\n   - b", selection: r(11))
        #expect(ap("1. a\n   - b", e) == "1. a\n- b" && e.selection == r(8), "outdent: bullet under ordered item, no stray space")
        #expect(ap("- a\n  1. b\n     - c", ListEdit.outdent(text: "- a\n  1. b\n     - c", selection: r(11))) == "- a\n  1. b\n  - c", "outdent: to parent item's indentation")
        #expect(ap("- a\n\n    - b", ListEdit.outdent(text: "- a\n\n    - b", selection: r(5))) == "- a\n\n- b", "outdent: over-indented item to parent, blank line between")
        #expect(ListEdit.isItem(text: "x\n  1. y", selection: r(3)) && ListEdit.isItem(text: "- [ ] t", selection: r(0)), "isItem: list lines")
        #expect(!ListEdit.isItem(text: "- a\nb", selection: r(4)) && !ListEdit.isItem(text: "", selection: r(0)), "isItem: plain lines")
        // Checkbox click: (text, insertion index, expected text or nil). swift-markdown (and so
        // the preview) has no task items inside block quotes, so neither does the click.
        let boxCases: [(String, Int, String?)] = [
            ("- [ ] a", 2, "- [x] a"), ("- [ ] a", 3, "- [x] a"), ("- [ ] a", 5, "- [x] a"),
            ("- [x] a", 4, "- [ ] a"), ("- [X] a", 3, "- [ ] a"), ("1. [ ] a", 4, "1. [x] a"),
            ("- [ ] a", 1, nil), ("- [ ] a", 6, nil), ("- [ ] a", 0, nil),
            ("- a [ ] b", 5, nil), ("`- [ ] a`", 3, nil), ("    - [ ] a", 7, nil),
            ("- [ ] a\n  - [x] b", 13, "- [ ] a\n  - [ ] b"), ("- [ ] a\n  - [x] b", 3, "- [x] a\n  - [x] b"),
            ("> - [ ] q", 5, nil), ("é\n\n- [ ] 👋", 6, "é\n\n- [x] 👋"), ("a\r\n\r\n* [ ] b", 8, "a\r\n\r\n* [x] b"),
        ]
        for (text, i, want) in boxCases {
            let e = ListEdit.toggleCheckbox(text: text, at: i)
            #expect(e.map { ap(text, $0) } == want && (e == nil || e!.selection == r(i)), "checkbox click at \(i) in \(text.debugDescription)")
        }
    }
}
