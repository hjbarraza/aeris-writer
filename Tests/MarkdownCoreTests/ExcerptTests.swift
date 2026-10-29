import Testing
import Foundation
@testable import MarkdownCore

struct ExcerptTests {
    @Test func empty() {
        #expect(Excerpt.make("") == "")
        #expect(Excerpt.make("  \n\n \t\n") == "")
    }
    @Test func markdownRemoved() {
        #expect(Excerpt.make("# Title\n\nBody text.") == "Title Body text.")
        #expect(Excerpt.make("Some **bold** and *soft* and ~~gone~~ words") == "Some bold and soft and gone words")
        #expect(Excerpt.make("See [the docs](http://example.com/x) now") == "See the docs now")
        #expect(Excerpt.make("Use `code` here\n\n```swift\nlet a = 1\n```") == "Use code here let a = 1")
        #expect(Excerpt.make("<div>hi</div>\n\nText") == "Text")
    }
    @Test func whitespaceCollapsed() {
        #expect(Excerpt.make("\n\n\nFirst line\n\n\n\nSecond   line") == "First line Second line")
    }
    @Test func frontMatterSkipped() {
        #expect(Excerpt.make("---\ntitle: T\ntags: [a]\n---\n\nBody") == "Body")
        #expect(Excerpt.make("---\ntitle: T\n---\n") == "")
    }
    @Test func limit() {
        #expect(Excerpt.make(String(repeating: "word ", count: 100)).count == 200)
        #expect(Excerpt.make("\u{FEFF}# Hi") == "Hi")
    }
    @Test func crlfFrontMatter() {
        #expect(Excerpt.make("---\r\ntitle: T\r\n---\r\n\r\nBody") == "Body")
        #expect(Excerpt.make("---\rtitle: T\r---\rBody") == "Body")
    }
    @Test func encodings() {
        #expect(Excerpt.make(data: Data(), truncated: false) == "")
        #expect(Excerpt.make(data: Data([0xFF, 0xFE]) + "# Hé".data(using: .utf16LittleEndian)!, truncated: false) == "Hé")
        #expect(Excerpt.make(data: "Café".data(using: .windowsCP1252)!, truncated: false) == "Café")
        #expect(Excerpt.make(data: Data([0, 1, 2, 0, 0xFF, 0x80, 0]), truncated: false) == nil)
        #expect(Excerpt.make(data: Data("ab😀😀😀".utf8).dropLast(2), truncated: true) == "ab😀😀")
        #expect(Excerpt.make(data: Data([0xFF, 0xFE]) + "ab😀".data(using: .utf16LittleEndian)!.dropLast(2), truncated: true) == "ab")
        #expect(Excerpt.make(data: Data("a\u{FFFD}b".utf8), truncated: false) == "ab")
    }
    @Test func unreadableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "excerpt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let locked = dir.appending(path: "locked.md")
        try "secret".write(to: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        #expect(Excerpt.ofFile(atPath: locked.path) == nil)
    }
}
