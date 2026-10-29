import Testing
import Foundation
@testable import MarkdownCore

// Mirrors Sources/mdcheck/DraftNameChecks.swift.
struct DraftNameTests {
    @Test func markersAndInlineMarkdownRemoved() {
        #expect(DraftName.make("# My Post") == "My Post")
        #expect(DraftName.make("### My Post\nsecond line") == "My Post")
        #expect(DraftName.make("- a list item") == "a list item")
        #expect(DraftName.make("1. first") == "first")
        #expect(DraftName.make("- [ ] a task") == "a task")
        #expect(DraftName.make("> quoted words") == "quoted words")
        #expect(DraftName.make("Some **bold** and *soft* [link](http://x.y) `code`") == "Some bold and soft link code")
    }
    @Test func unsafeCharactersReplacedAndTrimmed() {
        #expect(DraftName.make("Q3/Q4: plans") == "Q3-Q4- plans")
        #expect(DraftName.make("   padded   ") == "padded")
        #expect(DraftName.make("...hidden") == "hidden")
    }
    @Test func emptyIsUntitled() {
        for text in ["", "#", "\nsecond line only", "---"] { #expect(DraftName.make(text) == "Untitled") }
    }
    @Test func cappedOnAWordBoundary() {
        #expect(DraftName.make("one two three four five six seven eight nine ten eleven twelve thirteen")
                == "one two three four five six seven eight nine ten eleven")
        #expect(DraftName.make(String(repeating: "x", count: 70)) == String(repeating: "x", count: 60))
        #expect(DraftName.make(String(repeating: "word ", count: 30)).count <= 60)
    }
    @Test func cappedInBytes() {
        let family = "👨‍👩‍👧‍👦"
        let name = DraftName.make(String(repeating: family, count: 60))
        #expect(name.utf8.count <= DraftName.maxBytes && name.count == DraftName.maxBytes / 25)
        #expect(DraftName.make(family) == family)
    }
    @Test func invisibleControlsRemoved() {
        #expect(DraftName.make("A\u{200B}B\u{202E}C\u{2066}D\u{FEFF}") == "ABCD")
    }
    @Test func clashGetsANumber() {
        let taken: Set<String> = ["My Post.md", "My Post 2.md"]
        #expect(DraftName.unique("My Post", ext: "md") { taken.contains($0) } == "My Post 3.md")
        #expect(DraftName.unique("Fresh", ext: "txt") { taken.contains($0) } == "Fresh.txt")
    }
}
