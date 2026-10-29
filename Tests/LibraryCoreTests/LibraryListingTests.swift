import Testing
import Foundation
@testable import LibraryCore

struct LibraryListingTests {
    private func inc(_ name: String, dir: Bool = false, pkg: Bool = false, hidden: Bool = false) -> Bool {
        LibraryListing.includes(name: name, isDirectory: dir, isPackage: pkg, isHidden: hidden)
    }

    @Test func includes() {
        #expect(inc("a.MD"))
        #expect(inc("b.markdown"))
        #expect(inc("c.txt"))
        #expect(!(inc("d.json")))
        #expect(!(inc("md")))
        #expect(inc("notes.md", dir: true))
        #expect(!(inc("X.app", dir: true, pkg: true)))
        #expect(!(inc("Library", dir: true, hidden: true)))
    }

    @Test func sorted() {
        typealias E = LibraryEntry
        #expect(LibraryListing.sorted([E(name: "Note 10.md", isDirectory: false), E(name: "Note 2.md", isDirectory: false)]).map(\.name) == ["Note 2.md", "Note 10.md"])
        #expect(LibraryListing.sorted([E(name: "a.md", isDirectory: false), E(name: "A.md", isDirectory: false)]).map(\.name) == ["A.md", "a.md"])
    }

    @Test func canonicalPath() {
        #expect(LibraryListing.canonicalPath(URL(fileURLWithPath: "/tmp")) == "/private/tmp")
    }

    @Test func demoLibraryListing() {
        let demo = URL(fileURLWithPath: "docs/demo-library")
        #expect(LibraryListing.entries(in: demo).map(\.name) == ["Drafts", "Notes", "Welcome.md"])
        #expect(LibraryListing.entries(in: demo.appending(path: "Notes")).map(\.name) == ["Archive", "Meeting.txt"])
        #expect(LibraryListing.entries(in: demo.appending(path: "nope")).isEmpty)
    }

    @Test func packageAndFlaggedHiddenFiltered() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "lib-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appending(path: "Thing.app"), withIntermediateDirectories: true)
        fm.createFile(atPath: tmp.appending(path: "visible.md").path, contents: Data())
        fm.createFile(atPath: tmp.appending(path: "flagged.md").path, contents: Data())
        var flagged = tmp.appending(path: "flagged.md")
        var hidden = URLResourceValues(); hidden.isHidden = true
        try flagged.setResourceValues(hidden)
        #expect(LibraryListing.entries(in: tmp).map(\.name) == ["visible.md"])
    }
}
