import Testing
import Foundation
@testable import LibraryCore

struct QuickSearchContentTests {
    let doc = "# Alpha\nbeta here\n```\n# beta in code\n```\n## Beta two ##\n"

    @Test func headingsComeFirstThenText() {
        let found = QuickSearch.search(in: doc, query: "BETA", headings: true, text: true, maxFound: 10)
        #expect(found.map(\.kind) == [.heading(level: 2), .text, .text])
        #expect(found[0].snippet == "Beta two")
        #expect(found[0].line == 6)
    }

    @Test func filtersSelectKinds() {
        #expect(QuickSearch.search(in: doc, query: "beta", headings: false, text: true, maxFound: 10).count == 2)
        #expect(QuickSearch.search(in: doc, query: "beta", headings: true, text: false, maxFound: 10).count == 1)
        #expect(QuickSearch.search(in: doc, query: "beta", headings: false, text: false, maxFound: 10).isEmpty)
    }

    @Test func rangeIsUTF16() {
        let text = "\u{1F600} x\nsee beta"
        let m = QuickSearch.search(in: text, query: "beta", headings: true, text: true, maxFound: 5)
        #expect(m.map { (text as NSString).substring(with: $0.range) } == ["beta"])
    }
}
