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

    @Test func unsavedAndFileHostLinks() {
        let unsaved = { (href: String) in LinkAction.resolve(href, documentURL: nil).map { LinkAction.decide($0, documentURL: nil) } }
        #expect(unsaved("#x") == .scroll(anchor: "x"))
        #expect(unsaved("other.md#x") == nil && unsaved("other.md") == nil)
        #expect(unsaved("https://a.b/") == .system(URL(string: "https://a.b/")!))
        #expect(LinkAction.decide(URL(string: "file://host/x.md")!, documentURL: Self.doc) == .ignore)
        #expect(LinkAction.decide(URL(string: "file://localhost/tmp/notes/Other.md")!, documentURL: Self.doc) == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")))
        #expect(LinkAction.decide(URL(string: "file:///tmp/notes/Other.md")!, documentURL: Self.doc) == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")))
    }

    static let page = URL(fileURLWithPath: "/tmp/notes/")
    func nav(_ s: String, main: Bool = true, kind: NavigationKind = .other, own: Bool = false, page: URL? = page) -> NavigationPolicy {
        NavigationPolicy.decide(URL(string: s)!, isMainFrame: main, kind: kind, isOwnLoad: own, pageURL: page, documentURL: Self.doc)
    }
    @Test func navigationPolicy() {
        let page = Self.page
        #expect(nav(page.absoluteString, own: true) == .allow)
        #expect(nav(page.absoluteString) == .cancel)
        #expect(nav("https://example.com") == .cancel && nav("https://example.com", kind: .formSubmitted) == .cancel)
        #expect(nav("file:///tmp/notes/Other.md") == .cancel && nav("file:///etc/passwd") == .cancel)
        #expect(nav(page.absoluteString + "#x") == .allow)
        #expect(nav("file:///tmp/other/#x") == .cancel)
        #expect(nav("https://example.com", main: false) == .cancel && nav("file:///tmp/x.html", main: false) == .cancel)
        #expect(nav("about:blank", main: false) == .allow && nav("about:srcdoc", main: false) == .allow)
        #expect(nav("https://example.com", kind: .linkActivated) == .link(.system(URL(string: "https://example.com")!)))
        #expect(nav(page.absoluteString + "#x", kind: .formSubmitted) == .cancel && nav("about:blank#x", main: false, kind: .formSubmitted) == .cancel)
        #expect(nav("https://example.com", own: true) == .cancel && nav("file:///etc/passwd", own: true) == .cancel && nav("about:blank", own: true) == .allow)
        #expect(nav("about:blank#x", page: URL(string: "about:blank")) == .allow)
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
