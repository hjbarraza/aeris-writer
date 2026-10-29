import Testing
import Foundation
@testable import MarkdownCore

struct TextStatsTests {
    @Test func empty() {
        #expect(TextStats.compute("") == TextStats(characters: 0, charactersWithoutSpaces: 0, words: 0,
            sentences: 0, readingMinutes: 0, speakingMinutes: 0, tasksDone: 0, tasksTotal: 0))
    }
    @Test func headingSyntaxNotCounted() {
        let s = TextStats.compute("# Hello world")
        #expect(s.words == 2); #expect(s.characters == 11); #expect(s.charactersWithoutSpaces == 10)
    }
    @Test func linkURLNotCounted() {
        let s = TextStats.compute("See [two words](http://x.com/long/url) now")
        #expect(s.words == 4); #expect(s.characters == "See two words now".count)
    }
    /// Documents NLTokenizer behavior: an emoji is its own word token; 日本語 segments as 日本 + 語.
    @Test func emojiAndCJK() {
        #expect(TextStats.compute("Hi 🎉 there").words == 3)
        #expect(TextStats.compute("👨‍👩‍👧 a").characters == 3)
        let cjk = TextStats.compute("日本語")
        #expect(cjk.words == 2); #expect(cjk.characters == 3)
    }
    @Test func sentencesWithAbbreviation() {
        #expect(TextStats.compute("Use tools, e.g. a hammer. It works. Does it?").sentences == 3)
    }
    @Test func tasks() {
        let s = TextStats.compute("- [x] a\n- [X] b\n- [ ] c\n- plain")
        #expect(s.tasksDone == 2); #expect(s.tasksTotal == 3)
    }
    @Test func codeBlockCounted() {
        let s = TextStats.compute("```swift\nlet x = 1\n```")
        #expect(s.words == 3); #expect(s.characters == 9)
    }
    @Test func minutes() {
        #expect(TextStats.compute(Array(repeating: "word", count: 238).joined(separator: " ")).readingMinutes == 1)
        #expect(TextStats.compute(Array(repeating: "word", count: 140).joined(separator: " ")).speakingMinutes == 1)
    }
}
