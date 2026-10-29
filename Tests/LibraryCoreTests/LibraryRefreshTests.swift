import Testing
import Foundation
@testable import LibraryCore

@MainActor
struct LibraryRefreshTests {
    private func fc(_ p: String, scan: Bool = false) -> FolderChange {
        FolderChange(path: p, mustScanSubDirs: scan, rootChanged: false)
    }
    private func f(_ n: String) -> LibraryEntry { LibraryEntry(name: n, isDirectory: false) }

    @Test func plan() {
        #expect(RefreshPlan.directories(for: [fc("/r/a/")], loaded: ["/r", "/r/a"]) == ["/r/a"])
        #expect(RefreshPlan.directories(for: [fc("/")], loaded: ["/"]) == ["/"])
        #expect(RefreshPlan.directories(for: [fc("/r/x")], loaded: ["/r"]).isEmpty)
        #expect(RefreshPlan.directories(for: [fc("/r/a"), fc("/r/a"), fc("/r")], loaded: ["/r", "/r/a"]) == ["/r", "/r/a"])
        #expect(RefreshPlan.directories(for: [fc("/r", scan: true)], loaded: ["/r", "/r/a", "/r/a/b", "/rr"]) == ["/r", "/r/a", "/r/a/b"])
        #expect(RefreshPlan.directories(for: [FolderChange(path: "/r", mustScanSubDirs: false, rootChanged: true)], loaded: ["/r"]).isEmpty)
        #expect(RefreshPlan.directories(for: [fc("/big/unloaded/deep", scan: true)], loaded: ["/r"]).isEmpty)
    }

    @Test func diff() {
        let d = ChildDiff.diff(old: [f("a.md"), f("b.md"), f("c.md")], new: [f("a.md"), f("bb.md"), f("c.md"), f("d.md")])
        #expect(d.removed == IndexSet([1]))
        #expect(d.inserted == IndexSet([1, 3]))
        #expect(ChildDiff.diff(old: [], new: [f("a.md")]).inserted == IndexSet([0]))
        #expect(ChildDiff.diff(old: [f("a.md")], new: []).removed == IndexSet([0]))
        let same = ChildDiff.diff(old: [f("a.md")], new: [f("a.md")])
        #expect(same.removed.isEmpty && same.inserted.isEmpty)
        let kind = ChildDiff.diff(old: [f("x.md")], new: [LibraryEntry(name: "x.md", isDirectory: true)])
        #expect(kind.removed == IndexSet([0]))
        #expect(kind.inserted == IndexSet([0]))
    }

    @Test func refreshKeepsIdentityAndSkipsDetached() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "refresh-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp.appending(path: "sub"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        fm.createFile(atPath: tmp.appending(path: "a.md").path, contents: Data())
        fm.createFile(atPath: tmp.appending(path: "sub/s.md").path, contents: Data())
        let rootPath = LibraryListing.canonicalPath(tmp)
        let tree = LibraryTree(); tree.setRoots([tmp])
        tree.roots[0].loadChildren()
        let subNode = tree.roots[0].children![1]
        subNode.loadChildren()
        fm.createFile(atPath: tmp.appending(path: "b.md").path, contents: Data())
        try fm.removeItem(at: tmp.appending(path: "a.md"))
        fm.createFile(atPath: tmp.appending(path: "sub/t.md").path, contents: Data())
        let changes = tree.refresh([fc(rootPath), fc(rootPath + "/sub")])
        #expect(tree.roots[0].children?.map(\.name) == ["b.md", "sub"])
        #expect(tree.roots[0].children?[1] === subNode)
        #expect(subNode.children?.map(\.name) == ["s.md", "t.md"])
        #expect(changes.count == 2)
        #expect(changes[0].parent === tree.roots[0])
        #expect(tree.refresh([fc(rootPath)]).isEmpty)

        try fm.removeItem(at: tmp.appending(path: "sub"))
        let c2 = tree.refresh([fc(rootPath), fc(rootPath + "/sub")])
        #expect(c2.count == 1)
        #expect(tree.roots[0].children?.map(\.name) == ["b.md"])

        try fm.createDirectory(at: tmp.appending(path: "cold"), withIntermediateDirectories: true)
        _ = tree.refresh([fc(rootPath)])
        let cold = try #require(tree.roots[0].children?.first { $0.name == "cold" })
        _ = tree.refresh([fc(rootPath + "/cold", scan: true)])
        #expect(cold.children == nil)
    }

    @Test func unreadableFolderKeepsItsChildren() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "unreadable-\(UUID().uuidString)")
        let locked = tmp.appending(path: "locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: tmp)
        }
        fm.createFile(atPath: locked.appending(path: "l.md").path, contents: Data())
        let tree = LibraryTree(); tree.setRoots([tmp])
        tree.roots[0].loadChildren()
        let node = try #require(tree.roots[0].children?.first)
        node.loadChildren()
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        #expect(LibraryListing.read(locked) == nil)
        #expect(tree.refresh([fc(LibraryListing.canonicalPath(locked))]).isEmpty)
        #expect(node.children?.map(\.name) == ["l.md"])
    }
}
