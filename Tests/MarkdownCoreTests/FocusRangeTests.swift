import Testing
import Foundation
@testable import MarkdownCore

/// Mirrors Sources/mdcheck/FocusRangeChecks.swift.
struct FocusRangeTests {
    private func f(_ t: String, _ loc: Int, _ len: Int = 0, s: FocusRange.Scope) -> NSRange {
        FocusRange.range(in: t, selection: NSRange(location: loc, length: len), scope: s)
    }
    @Test func sentence() {
        #expect(f("One. Two. Three.", 6, s: .sentence) == NSRange(location: 5, length: 5))
        #expect(f("One. Two. Three.", 16, s: .sentence) == NSRange(location: 10, length: 6))
        #expect(f("One. Two. Three.", 2, 5, s: .sentence) == NSRange(location: 0, length: 10))
        #expect(f("First line\ncontinues. Next.", 2, s: .sentence) == NSRange(location: 0, length: 22))
    }
    @Test func paragraph() {
        #expect(f("a\nb c\n\nd", 3, s: .paragraph) == NSRange(location: 0, length: 6))
        #expect(f("a\nb c\n\nd", 6, s: .paragraph) == NSRange(location: 6, length: 1))
        #expect(f("a\nb c\n\nd", 8, s: .paragraph) == NSRange(location: 7, length: 1))
        #expect(f("a\n\nb", 0, 4, s: .paragraph) == NSRange(location: 0, length: 4))
        #expect(f("", 0, s: .sentence) == NSRange(location: 0, length: 0))
    }
}
