import Testing
import Foundation
@testable import MarkdownCore

struct MarkdownCoreTests {
    @Test func parsesHeadingAndParagraph() {
        let html = MarkdownCore.html("# Title\n\nHello **world**.")
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>world</strong>"))
    }

    @Test func escapesHTML() {
        let html = MarkdownCore.html("a < b & c")
        #expect(html.contains("a &lt; b &amp; c"))
    }

    /// Same fixtures as `mdcheck` (Tests/Fixtures), located relative to this file.
    @Test func fixtures() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }
        #expect(!(names.isEmpty))
        for name in names {
            let md = try String(contentsOf: dir.appendingPathComponent("\(name).md"), encoding: .utf8)
            let expected = try String(contentsOf: dir.appendingPathComponent("\(name).expected"), encoding: .utf8)
            let out = MarkdownCore.html(md, sourceLines: name.hasPrefix("lines-"))
            let lines = expected.split(separator: "\n")
            #expect(!(lines.isEmpty), "fixture \(name): empty .expected")
            for line in lines {
                let wanted = line.replacingOccurrences(of: "\\n", with: "\n")
                #expect(out.contains(wanted), "fixture \(name): missing \(wanted) in \(out)")
            }
        }
    }

    @Test func noAnchorsByDefault() {
        #expect(!(MarkdownCore.html("# a\n\nb").contains("data-line")))
    }

    /// Same table as `mdcheck` — keep the two identical.
    @Test func sourceLines() {
        let cases: [(String, Int, Int)] = [
            ("", 0, 1), ("abc", 2, 1), ("a\nb", 1, 1), ("a\nb", 2, 2), ("a\n\nc", 3, 3),
            ("a\r\nb", 2, 1), ("a\r\nb", 3, 2), ("a\rb", 2, 2), ("é👋\nx", 4, 2), ("a\nb", 99, 2),
        ]
        for (text, offset, want) in cases {
            #expect(SourceLines(text).line(at: offset) == want, "line at \(offset) in \(text.debugDescription)")
        }
    }

    /// Same table as `mdcheck` — keep the two identical.
    static let spanCases: [(String, [String])] = [
        ("", []),
        ("# Hi *there*", ["heading1@0+12", "syntax@0+2", "emphasis@5+7", "syntax@5+1", "syntax@11+1"]),
        ("T\n=", ["heading1@0+3", "syntax@1+2"]),
        ("**b**", ["strong@0+5", "syntax@0+2", "syntax@3+2"]),
        ("_e_", ["emphasis@0+3", "syntax@0+1", "syntax@2+1"]),
        ("~~s~~", ["strikethrough@0+5", "syntax@0+2", "syntax@3+2"]),
        ("`c`", ["inlineCode@0+3", "syntax@0+1", "syntax@2+1"]),
        ("``a`b``", ["inlineCode@0+7", "syntax@0+2", "syntax@5+2"]),
        ("[t](http://x)", ["link@0+13", "syntax@0+1", "syntax@2+11"]),
        ("![a](i.png)", ["image@0+11", "syntax@0+2", "syntax@3+8"]),
        ("```\n**not bold**\n```", ["codeBlock@0+20"]),
        ("> a\n> b", ["blockQuote@0+7", "syntax@0+1", "syntax@4+1"]),
        ("> a\n> *b*", ["blockQuote@0+9", "syntax@0+1", "syntax@4+1", "emphasis@6+3", "syntax@6+1", "syntax@8+1"]),
        ("- x", ["listMarker@0+2"]),
        ("1. y", ["listMarker@0+3"]),
        ("---", ["thematicBreak@0+3"]),
        ("é 👋 **b**", ["strong@5+5", "syntax@5+2", "syntax@8+2"]),
        ("中文 `c`", ["inlineCode@3+3", "syntax@3+1", "syntax@5+1"]),
        ("é\n\n*x*", ["emphasis@3+3", "syntax@3+1", "syntax@5+1"]),
        ("[👋](u)", ["link@0+7", "syntax@0+1", "syntax@3+4"]),
        ("# A\r\n\r\n**b**\r\n", ["heading1@0+3", "syntax@0+2", "strong@7+5", "syntax@7+2", "syntax@10+2"]),
        ("> a\r\n> b", ["blockQuote@0+8", "syntax@0+1", "syntax@5+1"]),
        ("é\r\n👋 _x_", ["emphasis@6+3", "syntax@6+1", "syntax@8+1"]),
        ("é *a*\r\n👋 **b**", ["emphasis@2+3", "syntax@2+1", "syntax@4+1", "strong@10+5", "syntax@10+2", "syntax@13+2"]),
    ]

    @Test func styleSpans() {
        for (input, expected) in Self.spanCases {
            let got = MarkdownCore.styleSpans(input).map(\.description)
            #expect(got.sorted() == expected.sorted(), "spans \(input.debugDescription)")
        }
    }

    @Test func styleSpansInRange() {
        let got = MarkdownCore.styleSpans("**a** _b_", in: NSRange(location: 6, length: 1)).map(\.description)
        #expect(got.sorted() == ["emphasis@6+3", "syntax@6+1"])
    }

    /// Mirrors mdcheck's RobustnessChecks.
    @Test func columnZeroLocationAndFuzz() {
        let lazyRowCode = "d\n` `\na||\n-|-"
        #expect(MarkdownCore.html(lazyRowCode).contains("<table>"))
        #expect(MarkdownCore.styleSpans(lazyRowCode).allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= 13 })
        let pieces = ["```\n", "\n", "\n\n", "# ", "**", "`", "` `", "- ", "> ", "    ", "|", "a||", "-|-", "<div>\n", "\\", "😀", "\r\n"]
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Int(seed % 1_000_000) }
        for _ in 0..<1000 {
            var s = ""
            for _ in 0..<(1 + next() % 12) { s += pieces[next() % pieces.count] }
            let n = (s as NSString).length
            #expect(MarkdownCore.styleSpans(s).allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= n })
            _ = MarkdownCore.html(s, sourceLines: true)
        }
        #expect(MarkdownCore.isInCodeBlock("```\nsetup\n\n- x\n```\n", at: 11))
    }
}
