import Testing
import Foundation
@testable import LibraryCore

@MainActor
struct FolderWatcherTests {
    @Test func changeReportedWithinOneSecondOnAliasedTempDir() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "aeris-watch-\(UUID())")  // /var alias of /private/var
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = LibraryListing.canonicalPath(dir)
        var got: [FolderChange] = []
        let w = FolderWatcher(paths: [path]) { got += $0 }
        try await Task.sleep(for: .milliseconds(300))
        let t0 = Date()
        FileManager.default.createFile(atPath: dir.appending(path: "new.md").path, contents: Data())
        while got.isEmpty && Date().timeIntervalSince(t0) < 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!(got.isEmpty))
        #expect(Date().timeIntervalSince(t0) < 1)
        #expect(RefreshPlan.directories(for: got, loaded: [path]) == [path])
        #expect(got.allSatisfy { !$0.rootChanged })
        w.stop()
        got = []
        FileManager.default.createFile(atPath: dir.appending(path: "after-stop.md").path, contents: Data())
        try await Task.sleep(for: .milliseconds(600))
        #expect(got.isEmpty)
    }
}
