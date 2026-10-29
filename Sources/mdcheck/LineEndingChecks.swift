import Foundation
import MarkdownCore

// LineEnding cases. Mirrored in Tests/MarkdownCoreTests/LineEndingTests.swift.
func runLineEndingChecks() {
    check(LineEnding.of("") == "\n" && LineEnding.of("one line") == "\n", "eol: none found -> LF")
    check(LineEnding.of("a\r\nb\nc") == "\r\n", "eol: first found wins (CRLF)")
    check(LineEnding.of("a\nb\r\nc") == "\n", "eol: first found wins (LF)")
    check(LineEnding.of("a\rb\n") == "\r", "eol: lone CR")
    check(LineEnding.convert("p1\np2\r\np3\rp4", to: "\r\n") == "p1\r\np2\r\np3\r\np4", "eol: convert to CRLF")
    check(LineEnding.convert("p1\r\np2\rp3\n", to: "\n") == "p1\np2\np3\n", "eol: convert to LF")
    check(LineEnding.convert("no breaks", to: "\r\n") == "no breaks", "eol: text without breaks unchanged")
    check(ListEdit.newline(text: "- a\r\n- b", selection: NSRange(location: 8, length: 0))?.replacement == "\r\n- ",
          "eol: list continuation in CRLF")
    check(BlockEdit.tableOfContents(text: "# A\r\n## B") == "- [A](#a)\r\n  - [B](#b)", "eol: toc in CRLF")
}
