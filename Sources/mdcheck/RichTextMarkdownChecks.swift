import Foundation
import MarkdownCore

// RichTextMarkdown cases. Mirrored in Tests/MarkdownCoreTests/RichTextMarkdownTests.swift.
func runRichTextMarkdownChecks() {
    func md(_ html: String) -> String? { RichTextMarkdown.convert(html: html) }
    check(md("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>")
          == "| A | B |\n| --- | --- |\n| 1 | 2 |", "richtext: 2x2 table -> pipe table with header row")
    check(md("<table><tbody><tr><td>x|y</td><td>b</td></tr><tr><td>c</td></tr></tbody></table>")
          == "| x\\|y | b |\n| --- | --- |\n| c |  |", "richtext: headerless table uses first row; pipes escaped; short rows padded")
    check(md("<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li><li>d</li></ul>")
          == "- a\n  - b\n    - c\n- d", "richtext: nested bullet list keeps nesting")
    check(md("<ol><li>one<ol><li>sub</li></ol></li><li>two</li></ol>")
          == "1. one\n   1. sub\n2. two", "richtext: nested numbered list")
    check(md("<ul class=ul1><li>a</li><ul class=ul1><li>b</li></ul><li>c</li></ul>")
          == "- a\n  - b\n- c", "richtext: nested list as sibling of items (Cocoa HTML)")
    check(md("<ol start=3><li>x</li><li>y</li></ol>") == "3. x\n4. y", "richtext: ordered list start")
    check(md("<p>See <a href=\"https://e.com/a b\">the <b>site</b></a>, <i>really</i>.</p>")
          == "See [the **site**](https://e.com/a%20b), *really*.", "richtext: link, bold, italic")
    check(md("<p>a <b> bold </b>b</p>") == "a **bold** b", "richtext: edge spaces stay outside markers")
    check(md("<b style=\"font-weight:normal\"><p>plain <span style=\"font-weight:700\">strong</span> "
             + "<span style=\"font-style:italic\">em</span></p></b>") == "plain **strong** *em*",
          "richtext: style-based emphasis; font-weight:normal wrapper is not bold")
    check(md("<p>one</p><p>two</p><h2>Head</h2><ul><li>x</li></ul>") == "one\n\ntwo\n\n## Head\n\n- x",
          "richtext: paragraphs, heading, list separated by blank lines")
    check(md("<p>a&nbsp;&amp;&lt;b&gt;&#65;&#x42; <code>x</code></p>") == "a &<b>AB `x`", "richtext: entities, inline code")
    check(md("<p>2 * 3 [x] snake_case _em_</p><a href=\"u\">l</a>") == "2 \\* 3 \\[x\\] snake_case \\_em\\_\n\n[l](u)",
          "richtext: markdown characters in text are escaped")
    check(md("<blockquote><p>q</p></blockquote>") == "> q", "richtext: blockquote")
    check(md("<pre><code>a\n  b</code></pre>") == "```\na\n  b\n```", "richtext: code block")
    check(md("<html><head><title>t</title><style>p{}</style></head><body><!--c--><script>x</script>"
             + "<ul><li>k</li></ul></body></html>") == "- k", "richtext: head, style, script and comments ignored")
    // Plain-ish HTML has no structure: nil, so the paste stays a plain paste.
    check(md("<p>just <span style=\"color:red\">text</span></p><div>more</div>") == nil, "richtext: unstructured HTML -> nil")
    check(md("") == nil && md("plain text, no tags") == nil, "richtext: empty and plain text -> nil")
    check(md("<ul><li>a<li>b</ul><p>x<p>y") == "- a\n- b\n\nx\n\ny", "richtext: unclosed li and p tags")
    // Round trip through our own renderer.
    let out = MarkdownCore.html(md("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>")!)
    check(out.contains("<table>") && out.contains("<th>A</th>") && out.contains("<td>2</td>"), "richtext: table renders as a table")
    let nested = MarkdownCore.html(md("<ul><li>a<ul><li>b</li></ul></li></ul><ol><li>x<ol><li>y</li></ol></li></ol>")!)
    check(nested.contains("<ul>") && nested.components(separatedBy: "<ul>").count == 3
          && nested.components(separatedBy: "<ol>").count == 3, "richtext: nested lists render nested")
    check(LineEnding.convert(md("<ul><li>a</li><li>b</li></ul>")!, to: "\r\n") == "- a\r\n- b", "richtext: result converts to CRLF")
}
