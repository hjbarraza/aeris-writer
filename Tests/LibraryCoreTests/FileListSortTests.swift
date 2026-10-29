import Testing
import Foundation
@testable import LibraryCore

// Mirrors Sources/mdcheck/FileListSortChecks.swift.
struct FileListSortTests {
    static func d(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }
    typealias I = FileListSort.Item
    let items = [
        I(name: "b.md", isDirectory: false, modified: d(300), created: d(10)),
        I(name: "A.txt", isDirectory: false, modified: d(100), created: d(30)),
        I(name: "zdir", isDirectory: true, modified: d(200), created: d(20)),
        I(name: "c.markdown", isDirectory: false, modified: d(400), created: d(5)),
        I(name: "adir", isDirectory: true, modified: d(50), created: d(40)),
    ]
    func order(_ key: SortKey, reversed: Bool = false, foldersOnTop: Bool = false) -> [String] {
        var o = FileListOptions()
        o.sortKey = key; o.reversed = reversed; o.foldersOnTop = foldersOnTop
        return FileListSort.sorted(items, options: o).map(\.name)
    }

    @Test func dates() {
        #expect(order(.dateModified) == ["c.markdown", "b.md", "zdir", "A.txt", "adir"])
        #expect(order(.dateModified, reversed: true) == ["adir", "A.txt", "zdir", "b.md", "c.markdown"])
        #expect(order(.dateCreated) == ["adir", "A.txt", "zdir", "b.md", "c.markdown"])
    }
    @Test func namesAndExtensions() {
        #expect(order(.name) == ["A.txt", "adir", "b.md", "c.markdown", "zdir"])
        #expect(order(.name, reversed: true) == ["zdir", "c.markdown", "b.md", "adir", "A.txt"])
        #expect(order(.fileExtension) == ["adir", "zdir", "c.markdown", "b.md", "A.txt"])
    }
    @Test func foldersOnTop() {
        #expect(order(.name, foldersOnTop: true) == ["adir", "zdir", "A.txt", "b.md", "c.markdown"])
        #expect(order(.dateModified, foldersOnTop: true) == ["zdir", "adir", "c.markdown", "b.md", "A.txt"])
    }
    @Test func optionsRoundTrip() {
        let suite = "test.filelist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FileListOptions.load(from: defaults) == FileListOptions())
        let custom = FileListOptions(sortKey: .fileExtension, reversed: true, foldersOnTop: true, showDate: .created,
                                     showExcerpts: false, navigation: .list, showSortBar: false)
        custom.save(to: defaults)
        #expect(FileListOptions.load(from: defaults) == custom)
    }
}
