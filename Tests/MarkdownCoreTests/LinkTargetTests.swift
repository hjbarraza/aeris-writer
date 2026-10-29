import Testing
import Foundation
@testable import MarkdownCore

struct LinkTargetTests {
    @Test func slugs() {
        #expect(HeadingSlugger.slug("Hello, World!") == "hello-world")
        #expect(HeadingSlugger.slug("A  B") == "a--b")
        #expect(HeadingSlugger.slug("Café Ünï_x-y 2") == "café-ünï_x-y-2")
    }
    @Test func duplicateSlugs() {
        var s = HeadingSlugger()
        #expect([s.next("Intro"), s.next("Intro"), s.next("Intro"), s.next("Intro-1")] == ["intro", "intro-1", "intro-2", "intro-1-1"])
    }
    @Test func headingIds() {
        let out = MarkdownCore.html("# Title\n\n## Second\n\n## Second\n\n## !!!")
        #expect(out.contains("<h1 id=\"title\">") && out.contains("<h2 id=\"second\">") && out.contains("<h2 id=\"second-1\">"))
        #expect(out.contains("<h2>!!!</h2>"))
        #expect(MarkdownCore.html("## `code` and *em*").contains("id=\"code-and-em\""))
    }

    static let doc = URL(fileURLWithPath: "/tmp/notes/Main.md")
    func decide(_ href: String) -> LinkAction {
        LinkAction.decide(LinkAction.resolve(href, documentURL: Self.doc)!, documentURL: Self.doc)
    }
    @Test func linkActions() {
        #expect(decide("#second") == .scroll(anchor: "second"))
        #expect(decide("#caf%C3%A9") == .scroll(anchor: "café"))
        #expect(decide("Other.md") == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")))
        #expect(decide("sub/My%20Note.md#top") == .openDocument(URL(fileURLWithPath: "/tmp/notes/sub/My Note.md")))
        #expect(decide("../up.md") == .openDocument(URL(fileURLWithPath: "/tmp/up.md")))
        #expect(decide("https://example.com/a") == .system(URL(string: "https://example.com/a")!))
        #expect(decide("mailto:a@b.c") == .system(URL(string: "mailto:a@b.c")!))
        #expect(decide("image.png") == .ignore && decide("ftp://x/y") == .ignore && decide("tel:1") == .ignore)
        #expect(LinkAction.decide(URL(string: "about:blank#second")!, documentURL: nil) == .scroll(anchor: "second"))
    }

    @Test func linkDestination() {
        let src = "é see [the **note**](Other.md \"t\") and `x`"
        #expect(MarkdownCore.linkDestination(in: src, at: 8) == "Other.md")
        #expect(MarkdownCore.linkDestination(in: src, at: 14) == "Other.md")
        #expect(MarkdownCore.linkDestination(in: src, at: 6) == "Other.md")
        #expect(MarkdownCore.linkDestination(in: src, at: 0) == nil)
        #expect(MarkdownCore.linkDestination(in: src, at: (src as NSString).length - 1) == nil)
    }
}
