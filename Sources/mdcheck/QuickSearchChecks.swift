import Foundation
import LibraryCore

@MainActor func runQuickSearchChecks() {
    typealias C = QuickSearch.Candidate
    func c(_ name: String, _ crumb: String = "Notes") -> C { C(path: "/r/\(crumb)/\(name)", fileName: name, breadcrumb: crumb) }
    func names(_ q: String, _ files: [C], ext: Bool = true) -> [String] {
        QuickSearch.rank(query: q, candidates: files, showExtension: ext).map(\.candidate.fileName)
    }
    let files = [c("Weekly review.md"), c("review notes.md"), c("My Preview.md"), c("Reading list.md"), c("zzz.md", "Reviews"), c("Other.md")]

    check(names("rev", files).prefix(2) == ["review notes.md", "Weekly review.md"],
          "quick search: prefix first, then word start (\(names("rev", files)))")
    check(names("rev", files).dropFirst(2).first == "My Preview.md", "quick search: substring after word start")
    check(names("rev", files).last == "My Preview.md" && names("evi", [c("zzz.md", "Reviews")]) == ["zzz.md"], "quick search: a folder-name match shows only when nothing better matches")
    check(!names("rev", files).contains("Other.md"), "quick search: non-matches dropped")
    check(names("rl", files).first == "Reading list.md", "quick search: fuzzy subsequence on the name")
    check(names("", files).isEmpty && names("   ", files).isEmpty, "quick search: empty query lists nothing")
    check(names("REVIEW", files).first == "review notes.md", "quick search: case-insensitive")
    check(names("cafe", [c("Caf\u{E9}.md"), c("zzz.md")]) == ["Caf\u{E9}.md"], "quick search: accents ignored")

    let r = QuickSearch.rank(query: "list", candidates: files, showExtension: true)
    check(r.first?.matched == [8..<12], "quick search: match range in the shown name (\(r.first?.matched ?? []))")
    check(names("md", files, ext: false).isEmpty, "quick search: hidden extension is not searched")
    check(names("md", files, ext: true).count == files.count, "quick search: shown extension is searched")
    check(QuickSearch.rank(query: "list", candidates: files, showExtension: false).first?.displayName == "Reading list",
          "quick search: display name without extension")

    // The weakest tail is dropped: a prefix match hides fuzzy-only matches.
    let tail = [c("alpha.md"), c("a l p h a.md"), c("axlxpxhxa.md")]
    check(names("alpha", tail) == ["alpha.md"], "quick search: weak tail dropped (\(names("alpha", tail)))")
    let many = (0..<200).map { c("note \($0).md") }
    check(QuickSearch.rank(query: "note", candidates: many, showExtension: true, limit: 20).count == 20, "quick search: result cap")

    // Enumeration: filtered like the sidebar, breadcrumbs relative to the root, cancellable.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appending(path: "mdcheck-qs-\(UUID().uuidString)")
    for d in ["Notes/Archive", "Drafts", ".hidden"] { try? fm.createDirectory(at: tmp.appending(path: d), withIntermediateDirectories: true) }
    for f in ["top.md", "Notes/a.md", "Notes/Archive/old.txt", "Drafts/d.md", "Notes/skip.json", ".hidden/h.md"] {
        fm.createFile(atPath: tmp.appending(path: f).path, contents: Data())
    }
    var found: [C] = []
    QuickSearch.enumerate(roots: [tmp], isCancelled: { false }) { found += $0 }
    let rootName = tmp.lastPathComponent
    check(Set(found.map(\.fileName)) == ["top.md", "a.md", "old.txt", "d.md"],
          "quick search enumerate: Markdown/text files, no hidden or other (\(found.map(\.fileName)))")
    check(found.first { $0.fileName == "old.txt" }?.breadcrumb == "\(rootName) \u{203A} Notes \u{203A} Archive",
          "quick search enumerate: breadcrumb")
    check(found.first { $0.fileName == "top.md" }?.breadcrumb == rootName, "quick search enumerate: file in the root")
    var calls = 0
    var seen: [C] = []
    QuickSearch.enumerate(roots: [tmp], isCancelled: { calls += 1; return calls > 2 }) { seen += $0 }
    check(seen.count < found.count, "quick search enumerate: stops when cancelled (\(seen.count) of \(found.count))")
    try? fm.removeItem(at: tmp)
}
