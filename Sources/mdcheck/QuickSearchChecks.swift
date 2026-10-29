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
    runQuickSearchContentChecks()
}

/// M2-23: matching inside files (pure).
@MainActor func runQuickSearchContentChecks() {
    typealias Hit = QuickSearch.ContentMatch
    let doc = "# Alpha plan\nIntro line about beta.\n\n## Beta notes\nMore beta text here.\n```\n# beta not a heading\n```\nCaf\u{E9} again, and BETA.\n"
    func find(_ q: String, headings: Bool = true, text: Bool = true, max: Int = 100) -> [Hit] {
        QuickSearch.search(in: doc, query: q, headings: headings, text: text, maxFound: max)
    }
    let all = find("beta")
    check(all.map(\.kind) == [.heading(level: 2), .text, .text, .text, .text],
          "content search: headings first (with level), then text in order (\(all.map(\.kind)))")
    check(all.first?.snippet == "Beta notes" && all.first?.line == 4, "content search: heading snippet is its title, line number")
    check(!all.contains { $0.snippet.contains("not a heading") && $0.kind != .text }, "content search: a # line in a code fence is text, not a heading")
    check(find("beta", headings: false).allSatisfy { $0.kind == .text } && find("beta", headings: false).count == 4,
          "content search: headings off -> text only")
    check(find("beta", text: false).map(\.kind) == [.heading(level: 2)], "content search: text off -> headings only")
    check(find("beta", headings: false, text: false).isEmpty && find("").isEmpty && find("  ").isEmpty, "content search: nothing on / empty query -> nothing")
    check(find("cafe").first?.snippet.hasPrefix("Caf\u{E9}") == true, "content search: case and accents ignored")
    let h = all[0]
    check((doc as NSString).substring(with: h.range).lowercased() == "beta", "content search: range is the match in the text (UTF-16)")
    check(find("beta", max: 2).count == 2, "content search: stops after maxFound")
    check(String(Array(all[0].snippet)[all[0].highlight]) == "Beta", "content search: highlight inside the snippet")
    let long = String(repeating: "word ", count: 60) + "needle " + String(repeating: "tail ", count: 60)
    let lh = QuickSearch.search(in: long, query: "needle", headings: true, text: true, maxFound: 5)
    check(lh.count == 1 && lh[0].snippet.count < 120 && String(Array(lh[0].snippet)[lh[0].highlight]) == "needle",
          "content search: long line -> short snippet around the match")
    let emoji = "\u{1F600} x\nsee beta"
    check(QuickSearch.search(in: emoji, query: "beta", headings: true, text: true, maxFound: 5).first.map { (emoji as NSString).substring(with: $0.range) } == "beta",
          "content search: UTF-16 offsets after an emoji")

    // Files: skipped when over the size cap, cancellable, capped by number of files.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appending(path: "mdcheck-qsc-\(UUID().uuidString)")
    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    let small = tmp.appending(path: "small.md"), big = tmp.appending(path: "big.md")
    try? Data("# needle\n".utf8).write(to: small)
    try? Data(repeating: 0x61, count: QuickSearch.maxFileBytes + 1).write(to: big)
    check(QuickSearch.readIfSmall(small.path) != nil && QuickSearch.readIfSmall(big.path) == nil, "content search: files over 2 MB are skipped")
    let link = tmp.appending(path: "link.md"), fifo = tmp.appending(path: "x.md")
    try? fm.createSymbolicLink(at: link, withDestinationURL: big)
    check(QuickSearch.readIfSmall(link.path) == nil, "content search: a symlink to a file over 2 MB is skipped")
    let smallLink = tmp.appending(path: "slink.md")
    try? fm.createSymbolicLink(at: smallLink, withDestinationURL: small)
    check(QuickSearch.readIfSmall(smallLink.path) != nil, "content search: a symlink to a small file is read")
    check(mkfifo(fifo.path, 0o644) == 0 && QuickSearch.readIfSmall(fifo.path) == nil, "content search: a FIFO named x.md is skipped without blocking")
    check(QuickSearch.readIfSmall(tmp.path) == nil, "content search: a directory is skipped")
    try? fm.removeItem(at: tmp)
    let manyLines = String(repeating: "beta\n", count: 5000)
    var asked = 0
    let partial = QuickSearch.search(in: manyLines, query: "beta", headings: true, text: true, maxFound: 100_000,
                                     isCancelled: { asked += 1; return true })
    check(partial.count < 5000 && asked >= 1, "content search: cancellation is checked inside a large file (\(partial.count) of 5000)")
    let cands = (0..<10).map { QuickSearch.Candidate(path: "/r/f\($0).md", fileName: "f\($0).md", breadcrumb: "R") }
    var delivered: [QuickSearch.FileHits] = []
    QuickSearch.searchFiles(query: "beta", candidates: cands, headings: true, text: true, maxFiles: 3,
                            read: { $0.fileName == "f1.md" ? "nothing" : doc }, isCancelled: { false }) { delivered.append($0) }
    check(delivered.map(\.candidate.fileName) == ["f0.md", "f2.md", "f3.md"], "content search: files without matches skipped, capped at maxFiles (\(delivered.map(\.candidate.fileName)))")
    var n = 0
    delivered = []
    QuickSearch.searchFiles(query: "beta", candidates: cands, headings: true, text: true, maxFiles: 10,
                            read: { _ in doc }, isCancelled: { n += 1; return n > 2 }) { delivered.append($0) }
    check(delivered.count == 2, "content search: stops when cancelled (\(delivered.count))")
}
