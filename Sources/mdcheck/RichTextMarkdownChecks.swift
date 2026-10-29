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
    check(md("<p>a&nbsp;&amp;&lt;b&gt;&#65;&#x42; <code>x</code></p>") == "a &\\<b\\>AB `x`", "richtext: entities, inline code")
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
    // Fix round 1: hostile and large input, escaping, plain-Paste mode.
    func timed(_ f: () -> String?) -> (String?, Double) {
        let t = Date(); let r = f(); return (r, Date().timeIntervalSince(t) * 1000)
    }
    let (spans, spanMs) = timed { md(String(repeating: "<span>", count: 5000) + "<b>x</b>") }
    check(spans == nil || spans!.count < 100_000, "richtext: 5000 nested spans -> no crash, bounded (\(Int(spanMs)) ms)")
    // Idle: spans ~6 ms, lists ~70 ms. Bounds leave room for parallel builds; the old code crashed or took 48 s.
    check(spanMs < 1000, "richtext: 5000 nested spans in under 1 s (\(Int(spanMs)) ms)")
    let (lists, listMs) = timed { md(String(repeating: "<ul><li>a", count: 10_000)) }
    check(lists != nil && lists!.utf8.count < 4_000_000, "richtext: 10k nested lists -> output bounded (\(lists?.utf8.count ?? 0) bytes)")
    check(listMs < 1000, "richtext: 10k nested lists in under 1 s (\(Int(listMs)) ms)")
    check(md("<ul><li>a</li></ul>" + String(repeating: "x", count: RichTextMarkdown.maxHTMLBytes)) == nil,
          "richtext: HTML over 2 MB is not converted")
    check(md("<p>&lt;script&gt;alert(1)&lt;/script&gt; &amp;lt; <a href=u>l</a></p>")
          == "\\<script\\>alert(1)\\</script\\> \\&lt; [l](u)", "richtext: decoded < > and entity-looking & are escaped")
    check(md("<p># not a heading</p><p>1. not a list</p><p>- nor this</p><p>&gt; nor quote</p><a href=u>l</a>")
          == "\\# not a heading\n\n1\\. not a list\n\n\\- nor this\n\n\\> nor quote\n\n[l](u)",
          "richtext: line-start markers in paragraphs are escaped")
    check(md("<pre>a ``` b\n````x</pre>") == "`````\na ``` b\n````x\n`````", "richtext: fence longer than any backtick run")
    check(md("<a href=\"javascript:alert(1)\">click</a> <a href=\"https://e.com\">ok</a>") == "click [ok](https://e.com)",
          "richtext: javascript: links keep their text only")
    check(RichTextMarkdown.convert(html: "<p>a <b>bold</b> <i>it</i> <code>c</code></p>", emphasisCounts: false) == nil,
          "richtext: plain-Paste mode: emphasis and inline code alone are not structure")
    check(RichTextMarkdown.convert(html: "<p>a <b>bold</b> <a href=u>l</a></p>", emphasisCounts: false) == "a **bold** [l](u)",
          "richtext: plain-Paste mode: a link still converts")
    // Fix round 2.
    let big = String(repeating: "<ul><li>a", count: 220_000)          // about 2 MB
    let (bigOut, bigMs) = timed { md(big) }
    check(bigOut == nil || bigOut!.utf8.count <= RichTextMarkdown.maxHTMLBytes, "richtext: 2 MB of nested lists -> output within the cap")
    // Idle: ~0.8 s debug. 5 s leaves room for parallel builds; the unbounded version froze for 9 s.
    check(bigMs < 5000, "richtext: 2 MB of nested lists converts in under 5 s (\(Int(bigMs)) ms)")
    let deep = String(repeating: "<ul><li>", count: 40) + "x"
    check(md(deep)!.split(separator: "\n").last!.prefix { $0 == " " }.count <= 64, "richtext: list indent stops at 16 levels")
    let tooDeep = String(repeating: "<div>", count: 300), closeAll = String(repeating: "</div>", count: 300)
    check(md(tooDeep + "<b>x" + closeAll + "<p>a <b>B</b> after</p>")!.hasSuffix("a **B** after"),
          "richtext: an unclosed overflowed <b> does not make a later bold run on")
    check(md(tooDeep + "<a href=x>q" + closeAll + "<p><a href=u>L</a> after</p>")!.hasSuffix("[L](u) after"),
          "richtext: an overflowed <a> does not make a later link run on")
    check(md(tooDeep + "<ul><li>k" + closeAll + "<ul><li>z</li></ul><p>para</p>")!.hasSuffix("\n\npara"),
          "richtext: an overflowed unclosed list does not absorb the next paragraph")
    check(md("<p>---</p><p>a<br>===</p><ul><li># h</li><li>1. x</li><li>- y</li></ul>")
          == "\\---\n\na\\\n\\===\n\n- \\# h\n- 1\\. x\n- \\- y", "richtext: rules, setext underlines and list-item markers are escaped")
    check(md("<a href=\"java&#x09;script:alert(1)\">y</a>") == nil, "richtext: a tab inside javascript: does not hide it (link dropped, no structure)")
}
