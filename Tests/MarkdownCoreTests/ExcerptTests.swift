import Testing
@testable import MarkdownCore

struct ExcerptTests {
    @Test func empty() {
        #expect(Excerpt.make("") == "")
        #expect(Excerpt.make("  \n\n \t\n") == "")
    }
    @Test func markdownRemoved() {
        #expect(Excerpt.make("# Title\n\nBody text.") == "Title Body text.")
        #expect(Excerpt.make("Some **bold** and *soft* and ~~gone~~ words") == "Some bold and soft and gone words")
        #expect(Excerpt.make("See [the docs](http://example.com/x) now") == "See the docs now")
        #expect(Excerpt.make("Use `code` here\n\n```swift\nlet a = 1\n```") == "Use code here let a = 1")
        #expect(Excerpt.make("<div>hi</div>\n\nText") == "Text")
    }
    @Test func whitespaceCollapsed() {
        #expect(Excerpt.make("\n\n\nFirst line\n\n\n\nSecond   line") == "First line Second line")
    }
    @Test func frontMatterSkipped() {
        #expect(Excerpt.make("---\ntitle: T\ntags: [a]\n---\n\nBody") == "Body")
        #expect(Excerpt.make("---\ntitle: T\n---\n") == "")
    }
    @Test func limit() {
        #expect(Excerpt.make(String(repeating: "word ", count: 100)).count == 200)
        #expect(Excerpt.make("\u{FEFF}# Hi") == "Hi")
    }
}
