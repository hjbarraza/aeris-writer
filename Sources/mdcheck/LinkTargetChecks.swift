import Foundation
import MarkdownCore

// Mirrored in Tests/MarkdownCoreTests/LinkTargetTests.swift.
func runLinkTargetChecks() {
    check(HeadingSlugger.slug("Hello, World!") == "hello-world", "slug: lowercase, punctuation dropped")
    check(HeadingSlugger.slug("A  B") == "a--b", "slug: each space becomes a hyphen")
    check(HeadingSlugger.slug("Café Ünï_x-y 2") == "café-ünï_x-y-2", "slug: letters, digits, _ and - kept")
    var s = HeadingSlugger()
    check([s.next("Intro"), s.next("Intro"), s.next("Intro"), s.next("Intro-1")] == ["intro", "intro-1", "intro-2", "intro-1-1"],
          "slug: duplicates get -1, -2 without colliding")

    let out = MarkdownCore.html("# Title\n\n## Second\n\n## Second\n\n## !!!")
    check(out.contains("<h1 id=\"title\">") && out.contains("<h2 id=\"second\">") && out.contains("<h2 id=\"second-1\">"),
          "heading ids in HTML")
    check(out.contains("<h2>!!!</h2>"), "heading with an empty slug gets no id")
    check(MarkdownCore.html("## `code` and *em*").contains("id=\"code-and-em\""), "heading id from plain text")

    let doc = URL(fileURLWithPath: "/tmp/notes/Main.md")
    func decide(_ href: String) -> LinkAction {
        // As WKWebView reports it: resolved against the page's base (the document's folder).
        LinkAction.decide(LinkAction.resolve(href, documentURL: doc)!, documentURL: doc)
    }
    check(decide("#second") == .scroll(anchor: "second"), "link: #anchor scrolls")
    check(decide("#caf%C3%A9") == .scroll(anchor: "café"), "link: anchor is percent-decoded")
    check(decide("Other.md") == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")), "link: relative .md opens")
    check(decide("sub/My%20Note.md#top") == .openDocument(URL(fileURLWithPath: "/tmp/notes/sub/My Note.md")), "link: spaces and fragment")
    check(decide("../up.md") == .openDocument(URL(fileURLWithPath: "/tmp/up.md")), "link: .. resolved")
    check(decide("https://example.com/a") == .system(URL(string: "https://example.com/a")!), "link: https to system")
    check(decide("mailto:a@b.c") == .system(URL(string: "mailto:a@b.c")!), "link: mailto to system")
    check(decide("image.png") == .ignore && decide("ftp://x/y") == .ignore && decide("tel:1") == .ignore, "link: other targets ignored")
    check(LinkAction.decide(URL(string: "about:blank#second")!, documentURL: nil) == .scroll(anchor: "second"), "link: anchor in an unsaved document")

    // Unsaved document: a relative link is ignored; #anchor still scrolls.
    let unsaved = { (href: String) in LinkAction.resolve(href, documentURL: nil).map { LinkAction.decide($0, documentURL: nil) } }
    check(unsaved("#x") == .scroll(anchor: "x"), "link: #anchor scrolls in an unsaved document")
    check(unsaved("other.md#x") == nil && unsaved("other.md") == nil && unsaved("https://a.b/") == .system(URL(string: "https://a.b/")!),"link: relative link in an unsaved document is ignored")
    check(LinkAction.decide(URL(string: "file://host/x.md")!, documentURL: doc) == .ignore, "link: file URL with a host is ignored")
    check(LinkAction.decide(URL(string: "file://localhost/tmp/notes/Other.md")!, documentURL: doc) == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")), "link: file://localhost is fine")
    check(LinkAction.decide(URL(string: "file:///tmp/notes/Other.md")!, documentURL: doc) == .openDocument(URL(fileURLWithPath: "/tmp/notes/Other.md")), "link: file:/// is fine")

    let page = URL(fileURLWithPath: "/tmp/notes/")
    func nav(_ s: String, main: Bool = true, kind: NavigationKind = .other, own: Bool = false, page: URL? = page) -> NavigationPolicy {
        NavigationPolicy.decide(URL(string: s)!, isMainFrame: main, kind: kind, isOwnLoad: own, pageURL: page, documentURL: doc)
    }
    check(nav(page.absoluteString, own: true) == .allow, "nav: our own load is allowed")
    check(nav(page.absoluteString) == .cancel, "nav: the page URL again (form, reload) is cancelled")
    check(nav("https://example.com") == .cancel && nav("https://example.com", kind: .formSubmitted) == .cancel, "nav: meta refresh or form to the web is cancelled")
    check(nav("file:///tmp/notes/Other.md") == .cancel && nav("file:///etc/passwd") == .cancel, "nav: no file page loads")
    check(nav(page.absoluteString + "#x") == .allow, "nav: in-page #anchor move is allowed")
    check(nav("file:///tmp/other/#x") == .cancel, "nav: #anchor on another page is cancelled")
    check(nav("https://example.com", main: false) == .cancel && nav("file:///tmp/x.html", main: false) == .cancel, "nav: remote or file subframes are cancelled")
    check(nav("about:blank", main: false) == .allow && nav("about:srcdoc", main: false) == .allow, "nav: blank subframes are allowed")
    check(nav("https://example.com", kind: .linkActivated) == .link(.system(URL(string: "https://example.com")!)), "nav: link clicks keep the link rules")
    check(nav(page.absoluteString + "#x", kind: .formSubmitted) == .cancel && nav("about:blank#x", main: false, kind: .formSubmitted) == .cancel,
          "nav: a form posting to #anchor is cancelled")
    check(nav("https://example.com", own: true) == .cancel && nav("file:///etc/passwd", own: true) == .cancel && nav("about:blank", own: true) == .allow,
          "nav: a lingering own-load credit admits no other URL")
    check(nav("about:blank#x", page: URL(string: "about:blank")) == .allow, "nav: #anchor in an unsaved document's page")

    let src = "é see [the **note**](Other.md \"t\") and `x`"
    let at = { (i: Int) in MarkdownCore.linkDestination(in: src, at: i) }
    check(at(8) == "Other.md" && at(14) == "Other.md" && at(6) == "Other.md", "linkDestination: inside the link text and on its markers")
    check(at(0) == nil && at((src as NSString).length - 1) == nil, "linkDestination: outside a link")
}
