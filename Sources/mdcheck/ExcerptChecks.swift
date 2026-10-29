import Foundation
import MarkdownCore
import LibraryCore

// Mirrored in Tests/MarkdownCoreTests/ExcerptTests.swift and Tests/LibraryCoreTests/RowDateTests.swift.
let excerptCases: [(String, String)] = [
    ("", ""),
    ("  \n\n \t\n", ""),
    ("# Title\n\nBody text.", "Title Body text."),
    ("Some **bold** and *soft* and ~~gone~~ words", "Some bold and soft and gone words"),
    ("See [the docs](http://example.com/x) now", "See the docs now"),
    ("Use `code` here\n\n```swift\nlet a = 1\n```", "Use code here let a = 1"),
    ("\n\n\nFirst line\n\n\n\nSecond   line", "First line Second line"),
    ("---\ntitle: T\ntags: [a]\n---\n\nBody", "Body"),
    ("---\ntitle: T\n---\n", ""),
    ("---\nnot closed\n\nBody", "not closed Body"),
    ("<div>hi</div>\n\nText", "Text"),
]

func runExcerptChecks() {
    for (input, want) in excerptCases {
        let got = Excerpt.make(input)
        if got != want { print("     got \(got.debugDescription)") }
        check(got == want, "excerpt \(input.debugDescription)")
    }
    check(Excerpt.make(String(repeating: "word ", count: 100)).count == 200, "excerpt: cut at 200 characters")
    check(Excerpt.make("\u{FEFF}# Hi") == "Hi", "excerpt: byte order mark ignored")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US")
    let formatter = RowDateFormatter(calendar: calendar, locale: locale)
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 14, minute: 30))!
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }
    check(formatter.label(for: at(15, 9, 5), now: now) == "9:05\u{202F}AM", "row date: today shows the time")
    check(formatter.label(for: at(14, 23, 59), now: now) == "Yesterday", "row date: yesterday late")
    check(formatter.label(for: at(14, 0, 0), now: now) == "Yesterday", "row date: yesterday midnight")
    check(formatter.label(for: at(13, 12), now: now) == "3/13/26", "row date: older shows the short date")
    check(formatter.label(for: at(16, 12), now: now) == "3/16/26", "row date: a future date shows the short date")
}
