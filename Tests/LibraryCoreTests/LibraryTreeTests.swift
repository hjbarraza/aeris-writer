import Testing
import Foundation
@testable import LibraryCore

@MainActor
struct LibraryTreeTests {
    @Test func lazyLoadingAndRootIdentity() throws {
        let demo = URL(fileURLWithPath: "docs/demo-library")
        let tmp = FileManager.default.temporaryDirectory
        let tree = LibraryTree(); tree.setRoots([demo])
        let root = tree.roots[0]
        #expect(root.children == nil)
        #expect(tree.loadedDirectoryPaths.isEmpty)
        root.loadChildren()
        #expect(root.children?.map(\.name) == ["Drafts", "Notes", "Welcome.md"])
        #expect(root.children?[1].children == nil)
        #expect(root.children?[2].children?.isEmpty == true)
        #expect(root.children?[0].path == root.path + "/Drafts")
        #expect(root.children?[0].parent === root)
        tree.setRoots([demo, tmp])
        #expect(tree.roots[0] === root)
        #expect(tree.roots.count == 2)
    }

    @Test func nodeAtPath() throws {
        let demo = URL(fileURLWithPath: "docs/demo-library")
        let t = LibraryTree(); t.setRoots([demo])
        let rootPath = LibraryListing.canonicalPath(demo)
        #expect(t.node(atPath: rootPath + "/Notes/Archive/Old note.md")?.name == "Old note.md")
        #expect(t.roots[0].children?.first { $0.name == "Notes" }?.children != nil)
        #expect(t.node(atPath: rootPath + "/Notes/data.json") == nil)
        #expect(t.node(atPath: "/elsewhere/x.md") == nil)
        t.setRoots([demo, demo.appending(path: "Notes")])
        #expect(t.node(atPath: rootPath + "/Notes/Meeting.txt")?.parent === t.roots[1])
    }
}
