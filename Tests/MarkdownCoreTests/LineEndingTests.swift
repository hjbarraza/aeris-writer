import Foundation
import Testing
@testable import MarkdownCore

// Mirrored in Sources/mdcheck/LineEndingChecks.swift.
struct LineEndingTests {
    @Test func firstFoundWins() {
        #expect(LineEnding.of("") == "\n")
        #expect(LineEnding.of("one line") == "\n")
        #expect(LineEnding.of("a\r\nb\nc") == "\r\n")
        #expect(LineEnding.of("a\nb\r\nc") == "\n")
        #expect(LineEnding.of("a\rb\n") == "\r")
    }

    @Test func convert() {
        #expect(LineEnding.convert("p1\np2\r\np3\rp4", to: "\r\n") == "p1\r\np2\r\np3\r\np4")
        #expect(LineEnding.convert("p1\r\np2\rp3\n", to: "\n") == "p1\np2\np3\n")
        #expect(LineEnding.convert("no breaks", to: "\r\n") == "no breaks")
    }

    @Test func editsUseTheDocumentsEnding() {
        #expect(ListEdit.newline(text: "- a\r\n- b", selection: NSRange(location: 8, length: 0))?.replacement == "\r\n- ")
        #expect(BlockEdit.tableOfContents(text: "# A\r\n## B") == "- [A](#a)\r\n  - [B](#b)")
    }
}
