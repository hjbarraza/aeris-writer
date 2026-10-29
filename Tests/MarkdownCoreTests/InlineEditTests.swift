import Testing
import Foundation
@testable import MarkdownCore

/// Mirrors Sources/mdcheck/InlineEditChecks.swift. Text marks the selection as
/// «…» or a caret as `|`, in both the input and the expected result.
struct InlineEditTests {
    private func cases() -> [(InlineMarker, String, String)] {
        let pairs: [(InlineMarker, String, String)] = [
            (.strong, "**", "**"), (.emphasis, "_", "_"), (.code, "`", "`"), (.strikethrough, "~~", "~~"),
            (.highlight, "==", "=="), (.wikilink, "[[", "]]"), (.comment, "<!-- ", " -->"),
            (.math, "$", "$"),
        ]
        var cases: [(InlineMarker, String, String)] = []
        for (m, o, c) in pairs {
            cases += [
                (m, "x «word» y", "x \(o)«word»\(c) y"),                 // wrap
                (m, "x \(o)«word»\(c) y", "x «word» y"),                 // unwrap, markers outside
                (m, "x «\(o)word\(c)» y", "x «word» y"),                 // unwrap, markers selected
                (m, "x wo|rd y", "x \(o)wo|rd\(c) y"),                   // caret in word: wrap
                (m, "x \(o)wo|rd\(c) y", "x wo|rd y"),                   // caret in word: unwrap
                (m, "x \(o)|\(c) y", "x | y"),                           // caret in empty pair
                (m, "x | y", "x \(o)|\(c) y"),                           // caret: insert pair
            ]
        }
        return cases + [
            (.emphasis, "**«bold»**", "**_«bold»_**"),
            (.emphasis, "**_«bold»_**", "**«bold»**"),
            (.emphasis, "*«it»*", "«it»"),
            (.emphasis, "**|**", "**_|_**"),
            (.strong, "***«x»***", "*«x»*"),
            (.strong, "__«x»__", "«x»"),
            (.comment, "«<!--x-->»", "«x»"),
            (.code, "«a`b»", "`` «a`b» ``"),
            (.code, "`` «a`b» ``", "«a`b»"),
            (.code, "«`` a`b ``»", "«a`b»"),
            (.code, "«a``b»", "``` «a``b» ```"),
            (.link, "see «docs» now", "see [docs](|) now"),
            (.link, "«https://x.io»", "[|](https://x.io)"),
            (.link, "a | b", "a [|]() b"),
            (.image, "«cat»", "![cat](|)"),
            (.image, "«https://x.io/c.png»", "![|](https://x.io/c.png)"),
            (.footnote, "Hi|.\n", "Hi[^1].\n\n[^1]: |"),
            (.footnote, "Hi|.\r\n", "Hi[^1].\r\n\r\n[^1]: |"),
            (.footnote, "A[^1] b|.\n\n[^1]: one\n", "A[^1] b[^2].\n\n[^1]: one\n\n[^2]: |"),
            (.footnote, "|", "[^1]\n\n[^1]: |"),
            (.strong, "👋 «héllo»", "👋 **«héllo»**"),
            (.strong, "👋 hé|llo 👋", "👋 **hé|llo** 👋"),
            (.highlight, "é **«👋»** é", "é **==«👋»==** é"),
            (.link, "a [te|xt](http://u) b", "a «text» b"),
            (.link, "a [«text»](u) b", "a «text» b"),
            (.link, "a «[text](u)» b", "a «text» b"),
            (.link, "[**b**|](u)", "«**b**»"),
            (.link, "[t](u)|", "[t](u)[|]()"),
            (.link, "[![a](i.png)|](u)", "«![a](i.png)»"),
            (.image, "x ![al|t](i.png)", "x «alt»"),
            (.image, "[![a|](i.png)](u)", "[«a»](u)"),
        ]
    }

    private func clearCases() -> [(String, String)] {
        [
            ("«**b** _i_ `c` ~~s~~ ==h== [t](u) ![a](i.png) [[w]]»", "«b i c s h t a w»"),
            ("x **b**| y\nnext **n**", "x b| y\nnext **n**"),
            ("# Head **b**|", "# Head b|"),
            ("- [ ] **t**|", "- [ ] t|"),
            ("**bo«ld** text»", "bo«ld text»"),
            ("«``  a`b  ``»", "« a`b »"),
            ("«`==x==`»", "«==x==»"),
            ("«[t](a==b==)»", "«t»"),
            ("«***x***»", "«x»"),
            ("«**==x==**»", "«x»"),
            ("«plain»", "«plain»"),
            ("```\n**x**|\n```", "```\n**x**|\n```"),
            ("<b>**x**</b>|", "<b>x</b>|"),
            ("«👋 **é**» z", "«👋 é» z"),
            ("a\r\n_b_|", "a\r\nb|"),
        ]
    }

    private func unmark(_ marked: String) -> (String, NSRange) {
        var s = marked as NSString
        let caret = s.range(of: "|")
        if caret.location != NSNotFound {
            return (s.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let a = s.range(of: "«"); s = s.replacingCharacters(in: a, with: "") as NSString
        let b = s.range(of: "»"); s = s.replacingCharacters(in: b, with: "") as NSString
        return (s as String, NSRange(location: a.location, length: b.location - a.location))
    }

    private func mark(_ text: String, _ edit: TextEdit) -> String {
        let out = NSMutableString(string: edit.applied(to: text))
        let sel = edit.selection
        if sel.length == 0 { out.insert("|", at: sel.location) } else {
            out.insert("»", at: NSMaxRange(sel)); out.insert("«", at: sel.location)
        }
        return out as String
    }

    @Test func toggleTable() {
        for (m, input, expected) in cases() {
            let (text, sel) = unmark(input)
            #expect(mark(text, InlineEdit.toggle(m, in: text, selection: sel)) == expected, "\(m) \(input)")
        }
    }

    @Test func clearStyles() {
        for (input, expected) in clearCases() {
            let (text, sel) = unmark(input)
            #expect(mark(text, InlineEdit.clearStyles(in: text, selection: sel)) == expected, Comment(rawValue: input))
        }
    }

    @Test func insertDateAndHashtag() {
        let day = Date(timeIntervalSince1970: 1_793_275_200)  // 2026-10-29 12:00 UTC
        let d = InlineEdit.insertDate(day, in: "a b c", selection: NSRange(location: 2, length: 1), timeZone: TimeZone(identifier: "UTC")!)
        #expect(d.applied(to: "a b c") == "a 2026-10-29 c")
        for (input, expected) in [("ab|cd", "ab #|cd"), ("ab |cd", "ab #|cd"), ("|", "#|"), ("«ab»", "#|")] {
            let (text, sel) = unmark(input)
            #expect(mark(text, InlineEdit.addHashtag(in: text, selection: sel)) == expected, Comment(rawValue: input))
        }
    }

    @Test func selectionClamped() {
        let e = InlineEdit.toggle(.strong, in: "ab", selection: NSRange(location: 5, length: 3))
        #expect(NSMaxRange(e.range) <= 2)
        #expect(e.applied(to: "ab") == "**ab**")
    }
}
