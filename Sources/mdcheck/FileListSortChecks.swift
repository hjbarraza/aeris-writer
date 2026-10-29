import Foundation
import LibraryCore

// Mirrored in Tests/LibraryCoreTests/FileListSortTests.swift.
func runFileListSortChecks() {
    func d(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }
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
    check(order(.dateModified) == ["c.markdown", "b.md", "zdir", "A.txt", "adir"], "sort: date modified newest first")
    check(order(.dateModified, reversed: true) == ["adir", "A.txt", "zdir", "b.md", "c.markdown"], "sort: date modified oldest first")
    check(order(.dateCreated) == ["adir", "A.txt", "zdir", "b.md", "c.markdown"], "sort: date created newest first")
    check(order(.dateCreated, reversed: true) == ["c.markdown", "b.md", "zdir", "A.txt", "adir"], "sort: date created oldest first")
    check(order(.name) == ["A.txt", "adir", "b.md", "c.markdown", "zdir"], "sort: name A to Z")
    check(order(.name, reversed: true) == ["zdir", "c.markdown", "b.md", "adir", "A.txt"], "sort: name Z to A")
    check(order(.fileExtension) == ["adir", "zdir", "c.markdown", "b.md", "A.txt"], "sort: extension A to Z, ties by name")
    check(order(.fileExtension, reversed: true) == ["A.txt", "b.md", "c.markdown", "adir", "zdir"], "sort: extension Z to A, ties by name")
    check(order(.name, foldersOnTop: true) == ["adir", "zdir", "A.txt", "b.md", "c.markdown"], "sort: folders on top, name")
    check(order(.name, reversed: true, foldersOnTop: true) == ["zdir", "adir", "c.markdown", "b.md", "A.txt"], "sort: folders on top, name reversed")
    check(order(.dateModified, foldersOnTop: true) == ["zdir", "adir", "c.markdown", "b.md", "A.txt"], "sort: folders on top, date")
    let undated = [I(name: "x.md", isDirectory: false, modified: nil, created: nil),
                   I(name: "y.md", isDirectory: false, modified: d(1), created: d(1))]
    check(FileListSort.sorted(undated, options: FileListOptions()).map(\.name) == ["y.md", "x.md"], "sort: a file without a date sorts as the oldest")

    // Defaults and persistence.
    let o = FileListOptions()
    check(o.sortKey == .dateModified && !o.reversed && !o.foldersOnTop && o.showDate == .modified
          && o.showExcerpts && o.navigation == .tree && o.showSortBar, "options: defaults")
    let suite = "mdcheck.filelist.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    check(FileListOptions.load(from: defaults) == FileListOptions(), "options: nothing stored loads the defaults")
    let custom = FileListOptions(sortKey: .fileExtension, reversed: true, foldersOnTop: true, showDate: .created,
                                 showExcerpts: false, navigation: .list, showSortBar: false)
    custom.save(to: defaults)
    check(FileListOptions.load(from: UserDefaults(suiteName: suite)!) == custom, "options: every option survives a save and load")
    defaults.set("nonsense", forKey: "FileList.sortKey")
    check(FileListOptions.load(from: defaults).sortKey == .dateModified, "options: an unknown stored value falls back to the default")
}
