import Foundation
import MarkdownCore

// InlineEdit cases. Text marks the selection as «…» or a caret as `|`, in both the
// input and the expected result. Mirrored in Tests/MarkdownCoreTests/InlineEditTests.swift.
func inlineEditCases() -> [(InlineMarker, String, String)] {
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

// Clear Formatting cases, same marking as above. Mirrored in InlineEditTests.
func clearStylesCases() -> [(String, String)] {
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

/// Strips «…» / `|` from `marked`, returning the text and the UTF-16 selection.
func unmarkSelection(_ marked: String) -> (String, NSRange) {
    var s = marked as NSString
    let caret = s.range(of: "|")
    if caret.location != NSNotFound {
        return (s.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
    }
    let a = s.range(of: "«"); s = s.replacingCharacters(in: a, with: "") as NSString
    let b = s.range(of: "»"); s = s.replacingCharacters(in: b, with: "") as NSString
    return (s as String, NSRange(location: a.location, length: b.location - a.location))
}

/// Applies `edit` to `text` and marks the resulting selection.
func markedResult(_ text: String, _ edit: TextEdit) -> String {
    let out = NSMutableString(string: edit.applied(to: text))
    let sel = edit.selection
    if sel.length == 0 { out.insert("|", at: sel.location) } else {
        out.insert("»", at: NSMaxRange(sel)); out.insert("«", at: sel.location)
    }
    return out as String
}

func runInlineEditChecks() {
    for (m, input, expected) in inlineEditCases() {
        let (text, sel) = unmarkSelection(input)
        let got = markedResult(text, InlineEdit.toggle(m, in: text, selection: sel))
        if got != expected { print("     got \(got.debugDescription)") }
        check(got == expected, "inline \(m) \(input.debugDescription)")
    }
    for (input, expected) in clearStylesCases() {
        let (text, sel) = unmarkSelection(input)
        let got = markedResult(text, InlineEdit.clearStyles(in: text, selection: sel))
        if got != expected { print("     got \(got.debugDescription)") }
        check(got == expected, "clear styles \(input.debugDescription)")
    }
    runInlineFuzz()
    // Out-of-bounds selection is clamped; the edit stays inside the text.
    let e = InlineEdit.toggle(.strong, in: "ab", selection: NSRange(location: 5, length: 3))
    check(NSMaxRange(e.range) <= 2 && e.applied(to: "ab") == "**ab**", "inline selection clamped")
}

func runInsertChecks() {
    // Insert Date: 2026-10-29 -> 2026-10-29, replacing a selection.
    let tz = TimeZone(identifier: "UTC")!
    let day = Date(timeIntervalSince1970: 1_793_275_200)  // 2026-10-29 12:00 UTC
    let d = InlineEdit.insertDate(day, in: "a «b» c".replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: ""),
                                  selection: NSRange(location: 2, length: 1), timeZone: tz)
    check(d.applied(to: "a b c") == "a 2026-10-29 c" && d.selection == NSRange(location: 12, length: 0), "insert date 2026-10-29")
    // Add Hashtag.
    for (input, expected) in [("ab|cd", "ab #|cd"), ("ab |cd", "ab #|cd"), ("|", "#|"), ("a\n|b", "a\n#|b"),
                              ("«ab»", "#|"), ("x «ab»", "x #|")] {
        let (text, sel) = unmarkSelection(input)
        let got = markedResult(text, InlineEdit.addHashtag(in: text, selection: sel))
        if got != expected { print("     got \(got.debugDescription)") }
        check(got == expected, "add hashtag \(input.debugDescription)")
    }
}

/// Toggling any inline marker, twice, on random marker-heavy text never removes or
/// adds a character that is not a marker character.
func runInlineFuzz() {
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
    check(bad == 0, "inline fuzz: toggling twice only ever changes marker characters (\(bad) bad)")
}
