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
            (.strong, "x« word »y", "x **«word»** y"),
            (.strong, "a« word »b", "a **«word»** b"),
            (.strong, "x «  word  » y", "x   **«word»**   y"),
            (.emphasis, "x _«w»_ y", "x «w» y"),
            (.emphasis, "x «_w_» y", "x «w» y"),
            (.emphasis, "*a* «b *c*»", "*a* *«b* *c*»"),
            (.strong, "**bo«ld** rest»", "**bo«ld** **rest»**"),
            (.strong, "«plain **bo**ld»", "**«plain** **bold»**"),
            (.strong, "__bo«ld__ rest»", "__bo«ld__ __rest»__"),
            (.strong, "«**a** **b**»", "«a b»"),
            (.strong, "**a «b» c**", "a «b» c"),
            (.strikethrough, "~~a~~ «b ~~c~~»", "~~a~~ ~~«b~~ ~~c~~»"),
            (.highlight, "==a== «b ==c==»", "==a== ==«b== ==c==»"),
            (.highlight, "«a ==b== c»", "==«a== ==b== ==c»=="),
            (.strong, "line one\n  **«bold»** more", "line one\n  «bold» more"),
            (.strong, "a\r\n  **«bold»** more", "a\r\n  «bold» more"),
            (.strong, "> a\n**«bold»** more", "> a\n«bold» more"),
            (.strong, "- a\nb **«bold»** more", "- a\nb «bold» more"),
            (.strong, "«a\n- **x**\n- y»", "**«a**\n- **x**\n- **y»**"),
            (.strong, "«a\n\nb»", "**«a**\n\n**b»**"),
            (.strong, "«> a\n> b»", "«> **a**\n> **b»**"),
            (.highlight, "x «==a=b==» y", "x «a=b» y"),
            (.highlight, "x ==«a=b»== y", "x «a=b» y"),
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

    /// Toggling any inline marker, twice, on random marker-heavy text never removes or
    /// adds a character that is not a marker character.
    @Test func inlineToggleFuzz() {
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        let atoms = ["a", "b", "é", "👋", " ", " ", "  ", "\n", "\r\n", "\n\n", "*", "**", "_", "__", "~~", "==", "> ", "- ", "1. ", "# ", "`", "[", "]"]
        let kinds: [InlineMarker] = [.strong, .emphasis, .strikethrough, .highlight]
        func plain(_ t: String) -> String { t.filter { !"*_~=".contains($0) } }
        var bad = 0
        for _ in 0..<2500 {
            var text = ""
            for _ in 0..<(3 + rnd(14)) { text += atoms[rnd(atoms.count)] }
            let ns = text as NSString
            var cuts = [0]
            while cuts.last! < ns.length { cuts.append(NSMaxRange(ns.rangeOfComposedCharacterSequence(at: cuts.last!))) }
            let a = rnd(cuts.count), b = rnd(cuts.count)
            var sel = NSRange(location: cuts[min(a, b)], length: cuts[max(a, b)] - cuts[min(a, b)])
            let m = kinds[rnd(kinds.count)]
            var cur = text
            for _ in 0..<2 {
                let e = InlineEdit.toggle(m, in: cur, selection: sel)
                cur = e.applied(to: cur)
                sel = e.selection
                if plain(cur) != plain(text) || NSMaxRange(sel) > (cur as NSString).length {
                    bad += 1; print("     fuzz \(m) \(text.debugDescription) -> \(cur.debugDescription)"); break
                }
            }
        }
        #expect(bad == 0, "toggling twice changed non-marker characters in \(bad) inputs")
    }
}
