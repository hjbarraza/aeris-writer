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
    ("---\r\ntitle: T\r\n---\r\n\r\nBody", "Body"),
    ("---\rtitle: T\r---\rBody", "Body"),
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

    // Raw bytes: the first 16 KB of a file, decoded by its own encoding. nil = can't be read as text.
    func bytes(_ s: String, _ e: String.Encoding) -> Data { s.data(using: e)! }
    check(Excerpt.make(data: Data(), truncated: false) == "", "excerpt data: empty file is empty text")
    check(Excerpt.make(data: Data([0xFF, 0xFE]) + bytes("# Hé", .utf16LittleEndian), truncated: false) == "Hé",
          "excerpt data: UTF-16 with BOM")
    check(Excerpt.make(data: bytes("Caf\u{E9} cr\u{E8}me", .windowsCP1252), truncated: false) == "Caf\u{E9} cr\u{E8}me",
          "excerpt data: Windows-1252 with accents")
    check(Excerpt.make(data: Data([0, 1, 2, 0, 0xFF, 0x80, 0]), truncated: false) == nil, "excerpt data: binary is nil")
    let cut = Data(("ab" + String(repeating: "\u{1F600}", count: 3)).utf8).dropLast(2)  // ends inside an emoji
    check(Excerpt.make(data: Data(cut), truncated: true) == "ab\u{1F600}\u{1F600}", "excerpt data: a cut UTF-8 tail is trimmed, not mojibake")
    let cut16 = Data([0xFF, 0xFE]) + bytes("ab\u{1F600}", .utf16LittleEndian).dropLast(2)  // ends between surrogates
    check(Excerpt.make(data: cut16, truncated: true) == "ab", "excerpt data: a cut UTF-16 tail is trimmed")
    check(Excerpt.make(data: Data("a\u{FFFD}b".utf8), truncated: false) == "ab", "excerpt data: U+FFFD never shown")

    let dir = FileManager.default.temporaryDirectory.appending(path: "excerpt-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let locked = dir.appending(path: "locked.md"), empty = dir.appending(path: "empty.md")
    try? "secret".write(to: locked, atomically: true, encoding: .utf8)
    FileManager.default.createFile(atPath: empty.path, contents: Data())
    try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    check(Excerpt.ofFile(atPath: locked.path) == nil, "excerpt file: unreadable is nil, not empty")
    check(Excerpt.ofFile(atPath: empty.path) == "", "excerpt file: empty file is empty text")
    check(Excerpt.ofFile(atPath: dir.appending(path: "gone.md").path) == nil, "excerpt file: missing is nil")

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
