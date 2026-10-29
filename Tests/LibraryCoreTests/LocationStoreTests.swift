import Testing
import Foundation
@testable import LibraryCore

struct LocationStoreTests {
    @Test func storeLifecycle() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "store-test-\(UUID().uuidString)")
        let folder = tmp.appending(path: "Notes")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let file = tmp.appending(path: "sub/Locations.plist")

        let s = LocationStore(fileURL: file); s.load()
        #expect(s.locations.isEmpty)
        #expect(try s.add(folder))
        #expect(!(try s.add(folder)))
        let s2 = LocationStore(fileURL: file); s2.load()
        #expect(s2.locations.count == 1)
        #expect(s2.resolve(at: 0).map(LibraryListing.canonicalPath) == LibraryListing.canonicalPath(folder))

        try fm.moveItem(at: folder, to: tmp.appending(path: "Renamed"))
        let s3 = LocationStore(fileURL: file); s3.load()
        #expect(s3.resolve(at: 0)?.lastPathComponent == "Renamed")
        #expect(s3.locations[0].path.hasSuffix("/Renamed"))
        let s3b = LocationStore(fileURL: file); s3b.load()
        #expect(s3b.locations[0].path.hasSuffix("/Renamed"))

        try fm.removeItem(at: tmp.appending(path: "Renamed"))
        let s4 = LocationStore(fileURL: file); s4.load()
        #expect(s4.resolve(at: 0) == nil)
        #expect(s4.locations.count == 1)
        try s4.remove(at: 0)
        let s5 = LocationStore(fileURL: file); s5.load()
        #expect(s5.locations.isEmpty)

        let trashFile = tmp.appending(path: "trash.plist"), victim = tmp.appending(path: "Trashed-\(UUID().uuidString)")
        try fm.createDirectory(at: victim, withIntermediateDirectories: true)
        let t = LocationStore(fileURL: trashFile); t.load()
        _ = try t.add(victim)
        let original = t.locations[0]
        var trashed: NSURL?
        try fm.trashItem(at: victim, resultingItemURL: &trashed)
        let t2 = LocationStore(fileURL: trashFile); t2.load()
        #expect(t2.resolve(at: 0) == nil)
        #expect(t2.locations[0] == original)
        try fm.moveItem(at: #require(trashed as URL?), to: victim)
        let t3 = LocationStore(fileURL: trashFile); t3.load()
        #expect(t3.resolve(at: 0).map(LibraryListing.canonicalPath) == LibraryListing.canonicalPath(victim))

        try Data("garbage".utf8).write(to: file)
        let s6 = LocationStore(fileURL: file); s6.load()
        #expect(s6.locations.isEmpty)
        #expect(s6.resolve(at: 3) == nil)
    }
}
