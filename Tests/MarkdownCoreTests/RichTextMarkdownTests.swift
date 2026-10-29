import Foundation
import Testing
@testable import MarkdownCore

// Mirrored (more fully) in Sources/mdcheck/RichTextMarkdownChecks.swift.
struct RichTextMarkdownTests {
    @Test func table() {
        #expect(RichTextMarkdown.convert(html: "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>")
                == "| A | B |\n| --- | --- |\n| 1 | 2 |")
    }

    @Test func nestedLists() {
        #expect(RichTextMarkdown.convert(html: "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>") == "- a\n  - b\n- c")
        #expect(RichTextMarkdown.convert(html: "<ol><li>one<ol><li>sub</li></ol></li><li>two</li></ol>")
                == "1. one\n   1. sub\n2. two")
    }

    @Test func inline() {
        #expect(RichTextMarkdown.convert(html: "<p>See <a href=\"https://e.com\">it</a>, <b>bold</b> <i>em</i></p>")
                == "See [it](https://e.com), **bold** *em*")
    }

    @Test func unstructuredIsNil() {
        #expect(RichTextMarkdown.convert(html: "<p>just <span>text</span></p>") == nil)
        #expect(RichTextMarkdown.convert(html: "plain") == nil)
    }
}
