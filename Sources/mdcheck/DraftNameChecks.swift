import Foundation
import MarkdownCore

// Mirrored in Tests/MarkdownCoreTests/DraftNameTests.swift.
let draftNameCases: [(String, String)] = [
    ("# My Post", "My Post"),
    ("### My Post\nsecond line", "My Post"),
    ("- a list item", "a list item"),
    ("1. first", "first"),
    ("- [ ] a task", "a task"),
    ("> quoted words", "quoted words"),
    ("Some **bold** and *soft* [link](http://x.y) `code`", "Some bold and soft link code"),
    ("Q3/Q4: plans", "Q3-Q4- plans"),
    ("   padded   ", "padded"),
    ("", "Untitled"),
    ("#", "Untitled"),
    ("\nsecond line only", "Untitled"),
    ("---", "Untitled"),
    ("...hidden", "hidden"),
    ("one two three four five six seven eight nine ten eleven twelve thirteen",
     "one two three four five six seven eight nine ten eleven"),
    (String(repeating: "x", count: 70), String(repeating: "x", count: 60)),
]

func runDraftNameChecks() {
    for (input, want) in draftNameCases {
        let got = DraftName.make(input)
        if got != want { print("     got \(got.debugDescription)") }
        check(got == want, "draft name \(input.debugDescription)")
    }
    check(DraftName.make(String(repeating: "word ", count: 30)).count <= 60, "draft name: at most 60 characters")
    let family = "👨‍👩‍👧‍👦"  // 25 UTF-8 bytes in one character
    let emoji = DraftName.make(String(repeating: family, count: 60))
    check(emoji.utf8.count <= DraftName.maxBytes && emoji.count == DraftName.maxBytes / 25,
          "draft name: capped at \(DraftName.maxBytes) UTF-8 bytes (got \(emoji.utf8.count) bytes)")
    check(DraftName.make("A\u{200B}B\u{202E}C\u{2066}D\u{FEFF}") == "ABCD", "draft name: zero-width and bidi controls removed")
    check(DraftName.make(family) == family, "draft name: emoji joiners kept")
    let taken: Set<String> = ["My Post.md", "My Post 2.md"]
    check(DraftName.unique("My Post", ext: "md") { taken.contains($0) } == "My Post 3.md", "draft name: clash gets ' 3'")
    check(DraftName.unique("Fresh", ext: "txt") { taken.contains($0) } == "Fresh.txt", "draft name: no clash keeps the name")
}
