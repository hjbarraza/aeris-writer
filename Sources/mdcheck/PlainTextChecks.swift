import Foundation
import MarkdownCore

// Mirrored in Tests/MarkdownCoreTests/PlainTextTests.swift.
let plainTextCases: [(String, String)] = [
    ("", ""),
    ("# Title\n\nBody text.", "Title\n\nBody text."),
    ("## A **b** *c* ~~d~~ `e`", "A b c d e"),
    ("See [the docs](http://example.com/x) now", "See the docs now"),
    ("Pic ![a cat](cat.png) here", "Pic a cat here"),
    ("- one\n- two\n  - nested", "• one\n• two\n  • nested"),
    ("1. a\n2. b", "1. a\n2. b"),
    ("3. a\n4. b", "3. a\n4. b"),
    ("- [x] done\n- [ ] todo", "• ☑ done\n• ☐ todo"),
    ("```swift\nlet a = 1\n```", "let a = 1"),
    ("> quoted *text*", "quoted text"),
    ("| A | B |\n|---|---|\n| 1 | 2 |", "A\tB\n1\t2"),
    ("one\\*two", "one*two"),
    ("a\nb", "a b"),
    ("a  \nb", "a\nb"),
    ("a\n\n---\n\nb", "a\n\nb"),
    ("<div>x</div>\n\nText", "Text"),
    ("- a\n\n  para\n- b", "• a\n\n  para\n• b"),
    ("---\ntitle: X\n---\n\n# Hi\n", "Hi"),
    ("---\r\ntitle: X\r\n---\r\n\r\n# Hi\r\n", "Hi"),
    ("---\nnot closed\n\nBody", "not closed\n\nBody"),
    ("Hello<br>there<br/>x", "Hello\nthere\nx"),
    ("text[^1] more\n\n[^1]: the *note*", "text[1] more\n\n[1] the note"),
]

func runPlainTextChecks() {
    for (input, want) in plainTextCases {
        let got = PlainText.make(input)
        if got != want { print("     got \(got.debugDescription)") }
        check(got == want, "plain text \(input.debugDescription)")
    }
    let doc = "# H\n\n*a* **b** [c](u) ![d](i) `e` ~~f~~\n\n- x\n"
    let out = PlainText.make(doc)
    check(!out.contains(where: { "#*[]()`~".contains($0) }), "plain text: no Markdown characters left (got \(out.debugDescription))")
    let dirty = "<p>a<img src=\"http://x.example/i.png\" alt=\"i\"></p><script>x()</script><link rel=\"stylesheet\" href=\"http://x\"><p style=\"background:url(http://y)\"><b>b</b></p>"
    let clean = RichTextHTML.withoutResources(dirty)
    check(!clean.contains("http") && !clean.contains("script") && clean.contains("<b>b</b>") && clean.contains("alt=\"i\""),
          "rich text html: remote resources removed, formatting kept (got \(clean.debugDescription))")
}
