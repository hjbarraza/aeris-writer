// CLT-runnable smoke test for MarkdownCore (this machine has Command Line Tools
// only, where `swift test` can't load XCTest/swift-testing). Run: `swift run mdcheck`
// from the repo root. The XCTest suite in Tests/ is the real test harness for
// machines with full Xcode / CI; both load the same Tests/Fixtures.
import Foundation
import MarkdownCore

func check(_ cond: Bool, _ label: String) {
    print(cond ? "ok   - \(label)" : "FAIL - \(label)")
    if !cond { exit(1) }
}

let html = MarkdownCore.html("# Title\n\nHello **world**.")
check(html.contains("<h1 id=\"title\">Title</h1>"), "heading renders")
check(html.contains("<strong>world</strong>"), "strong renders")
let page = MarkdownCore.htmlDocument(body: "<p>hi</p>", title: "T <x>")
check(page.contains("<p>hi</p>") && page.contains("name=\"color-scheme\" content=\"light dark\"")
      && page.contains("prefers-color-scheme: dark") && page.contains("T &lt;x&gt;"), "htmlDocument template")
check(MarkdownCore.html("a < b & c").contains("a &lt; b &amp; c"), "html escaped")

// Fixtures: name.md is rendered; each non-empty line of name.expected is a
// required substring of the HTML (a literal `\n` in a line means a newline).
// Fixtures named `lines-*` render with source-line anchors (`data-line`).
let fixtureDir = "Tests/Fixtures"
let names = ((try? FileManager.default.contentsOfDirectory(atPath: fixtureDir)) ?? [])
    .filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
check(!names.isEmpty, "fixtures found in \(fixtureDir) (run from repo root)")
for name in names {
    let md = (try? String(contentsOfFile: "\(fixtureDir)/\(name).md", encoding: .utf8)) ?? ""
    let expected = (try? String(contentsOfFile: "\(fixtureDir)/\(name).expected", encoding: .utf8)) ?? ""
    let out = MarkdownCore.html(md, sourceLines: name.hasPrefix("lines-"))
    let wanted = expected.split(separator: "\n").map { $0.replacingOccurrences(of: "\\n", with: "\n") }
    check(!wanted.isEmpty && wanted.allSatisfy { out.contains($0) }, "fixture \(name)")
}

check(!MarkdownCore.html("# a\n\nb").contains("data-line"), "no anchors by default")

// Source lines: (text, utf16 offset, expected 1-based line). Mirrored in Tests/MarkdownCoreTests.
let lineCases: [(String, Int, Int)] = [
    ("", 0, 1), ("abc", 2, 1), ("a\nb", 1, 1), ("a\nb", 2, 2), ("a\n\nc", 3, 3),
    ("a\r\nb", 2, 1), ("a\r\nb", 3, 2), ("a\rb", 2, 2), ("é👋\nx", 4, 2), ("a\nb", 99, 2),
]
for (text, offset, want) in lineCases {
    check(SourceLines(text).line(at: offset) == want, "line at \(offset) in \(text.debugDescription) = \(want)")
}

// Style spans: (input, expected `kind@utf16start+length`), order-insensitive.
// Mirrored in Tests/MarkdownCoreTests — keep the two tables identical.
let spanCases: [(String, [String])] = [
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
    // Non-ASCII before a span: é = 2 UTF-8 bytes/1 UTF-16 unit, 👋 = 4/2, 中 = 3/1.
    ("é 👋 **b**", ["strong@5+5", "syntax@5+2", "syntax@8+2"]),
    ("中文 `c`", ["inlineCode@3+3", "syntax@3+1", "syntax@5+1"]),
    ("é\n\n*x*", ["emphasis@3+3", "syntax@3+1", "syntax@5+1"]),
    ("[👋](u)", ["link@0+7", "syntax@0+1", "syntax@3+4"]),
    // CRLF line endings.
    ("# A\r\n\r\n**b**\r\n", ["heading1@0+3", "syntax@0+2", "strong@7+5", "syntax@7+2", "syntax@10+2"]),
    ("> a\r\n> b", ["blockQuote@0+8", "syntax@0+1", "syntax@5+1"]),
    ("é\r\n👋 _x_", ["emphasis@6+3", "syntax@6+1", "syntax@8+1"]),
    ("é *a*\r\n👋 **b**", ["emphasis@2+3", "syntax@2+1", "syntax@4+1", "strong@10+5", "syntax@10+2", "syntax@13+2"]),
]
for (input, expected) in spanCases {
    let got = MarkdownCore.styleSpans(input).map(\.description)
    let ok = got.sorted() == expected.sorted()
    if !ok { print("     got \(got)") }
    check(ok, "spans \(input.debugDescription)")
}
let ranged = MarkdownCore.styleSpans("**a** _b_", in: NSRange(location: 6, length: 1)).map(\.description)
check(ranged.sorted() == ["emphasis@6+3", "syntax@6+1"], "spans in range")

// Timing (informational): ~50k words. Use `swift run -c release mdcheck` for a real number.
let para = "Some *emphasis*, some **strong** text, a [link](https://example.com) and `code` here. "
let big = (0..<505).map { "## Section \($0)\n\n- item one\n- item two\n\n" + String(repeating: para, count: 9) + "\n\n" }.joined()
let words = big.split(whereSeparator: \.isWhitespace).count
let t0 = Date()
let bigSpans = MarkdownCore.styleSpans(big)
print(String(format: "info - styleSpans on %d words: %.0f ms, %d spans", words, Date().timeIntervalSince(t0) * 1000, bigSpans.count))
runTextStatsChecks()
runExcerptChecks()
runTextEncodingChecks()
runInlineEditChecks()
runBlockEditChecks()
runTableEditChecks()
runLineEndingChecks()
runFocusRangeChecks()
runAutocompleteChecks()
runLinkTargetChecks()
runRobustnessChecks()
runLibraryChecks()
runLibraryRefreshChecks()
runFolderWatcherChecks()
try runLocationStoreChecks()
print("mdcheck passed")
