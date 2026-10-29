import Testing
import Foundation
@testable import MarkdownCore

// Mirrors Sources/mdcheck/PlainTextChecks.swift.
struct PlainTextTests {
    @Test func blocksAndInline() {
        #expect(PlainText.make("") == "")
        #expect(PlainText.make("# Title\n\nBody text.") == "Title\n\nBody text.")
        #expect(PlainText.make("## A **b** *c* ~~d~~ `e`") == "A b c d e")
        #expect(PlainText.make("See [the docs](http://example.com/x) now") == "See the docs now")
        #expect(PlainText.make("Pic ![a cat](cat.png) here") == "Pic a cat here")
        #expect(PlainText.make("one\\*two") == "one*two")
        #expect(PlainText.make("a\nb") == "a b")
        #expect(PlainText.make("a  \nb") == "a\nb")
        #expect(PlainText.make("a\n\n---\n\nb") == "a\n\nb")
        #expect(PlainText.make("<div>x</div>\n\nText") == "Text")
        #expect(PlainText.make("> quoted *text*") == "quoted text")
        #expect(PlainText.make("```swift\nlet a = 1\n```") == "let a = 1")
    }
    @Test func lists() {
        #expect(PlainText.make("- one\n- two\n  - nested") == "• one\n• two\n  • nested")
        #expect(PlainText.make("1. a\n2. b") == "1. a\n2. b")
        #expect(PlainText.make("3. a\n4. b") == "3. a\n4. b")
        #expect(PlainText.make("- [x] done\n- [ ] todo") == "• ☑ done\n• ☐ todo")
        #expect(PlainText.make("- a\n\n  para\n- b") == "• a\n\n  para\n• b")
    }
    @Test func tables() {
        #expect(PlainText.make("| A | B |\n|---|---|\n| 1 | 2 |") == "A\tB\n1\t2")
    }
}
