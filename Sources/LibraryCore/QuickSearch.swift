import Foundation

/// Quick search over file names: lazy enumeration of the library (no index, no file contents)
/// and fuzzy ranking of the names it finds.
public enum QuickSearch {
    /// One file the search can find.
    public struct Candidate: Equatable, Sendable {
        public let path: String
        public let fileName: String
        /// The folder trail below the location, e.g. "Notes › Archive" (the location's own name first).
        public let breadcrumb: String
        /// `fileName` and `breadcrumb` lowercased and without accents, one character per character.
        let foldedName: [Character]
        let foldedCrumb: [Character]

        public init(path: String, fileName: String, breadcrumb: String) {
            self.path = path
            self.fileName = fileName
            self.breadcrumb = breadcrumb
            foldedName = fileName.map(QuickSearch.fold)
            foldedCrumb = breadcrumb.map(QuickSearch.fold)
        }
    }

    public struct Result: Equatable, Sendable {
        public let candidate: Candidate
        /// The name as shown (without its extension when extensions are hidden).
        public let displayName: String
        /// Character offsets in `displayName` to highlight; empty when only the folder matched.
        public let matched: [Range<Int>]
        public let score: Int
    }

    static func fold(_ c: Character) -> Character {
        let s = String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return s.first ?? c
    }

    // MARK: Ranking

    /// Best match first: name prefix, word start, substring, letters in order, then a match on the
    /// folder trail. Results scoring under half the best one are dropped, and at most `limit` stay.
    /// An empty query matches nothing.
    public static func rank(query: String, candidates: [Candidate], showExtension: Bool, limit: Int = 50) -> [Result] {
        let q = Array(query.trimmingCharacters(in: .whitespaces).map(fold))
        guard !q.isEmpty else { return [] }
        let compact = q.filter { !$0.isWhitespace }
        let tokens = q.split(separator: " ").map(Array.init)
        var scored: [Result] = []
        for cand in candidates {
            if Task.isCancelled { return [] }
            let display = showExtension ? cand.fileName : (cand.fileName as NSString).deletingPathExtension
            let name = Array(cand.foldedName.prefix(display.count))
            guard let (score, ranges) = match(q, compact, tokens, name: name, crumb: cand.foldedCrumb) else { continue }
            scored.append(Result(candidate: cand, displayName: display, matched: ranges, score: score))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.displayName.count != $1.displayName.count { return $0.displayName.count < $1.displayName.count }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        guard let best = scored.first?.score else { return [] }
        return Array(scored.prefix { $0.score * 2 >= best }.prefix(limit))
    }

    private static func match(_ q: [Character], _ compact: [Character], _ tokens: [[Character]],
                              name: [Character], crumb: [Character]) -> (Int, [Range<Int>])? {
        if name.starts(with: q) { return (1000, [0..<q.count]) }
        if let i = firstIndex(of: q, in: name, wordStartOnly: true) { return (800 - min(i, 99), [i..<i + q.count]) }
        if let i = firstIndex(of: q, in: name, wordStartOnly: false) { return (600 - min(i, 99), [i..<i + q.count]) }
        if let hits = subsequence(compact, in: name) {
            let gaps = hits.last! - hits.first! + 1 - compact.count
            return (400 - min(gaps, 200), ranges(of: hits))
        }
        let trail = crumb + [" "] + name
        if tokens.count > 1, tokens.allSatisfy({ firstIndex(of: $0, in: trail, wordStartOnly: false) != nil }) { return (150, []) }
        if let hits = subsequence(compact, in: trail) {
            return (100 - min(hits.last! - hits.first! + 1 - compact.count, 50), [])
        }
        return nil
    }

    private static func firstIndex(of q: [Character], in text: [Character], wordStartOnly: Bool) -> Int? {
        guard q.count <= text.count else { return nil }
        for i in 0...(text.count - q.count) where text[i..<i + q.count].elementsEqual(q) {
            if !wordStartOnly || (i > 0 && !text[i - 1].isLetter && !text[i - 1].isNumber) { return i }
        }
        return nil
    }

    /// Indices of the first in-order occurrence of `q`'s characters in `text`.
    private static func subsequence(_ q: [Character], in text: [Character]) -> [Int]? {
        var hits: [Int] = [], at = 0
        for (i, ch) in text.enumerated() where at < q.count && ch == q[at] {
            hits.append(i); at += 1
        }
        return at == q.count ? hits : nil
    }

    private static func ranges(of hits: [Int]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for i in hits {
            if let last = out.last, last.upperBound == i { out[out.count - 1] = last.lowerBound..<i + 1 } else { out.append(i..<i + 1) }
        }
        return out
    }

    // MARK: Enumeration

    /// Walks every location depth-first, the way the sidebar lists it (Markdown/text files, no
    /// hidden items), and hands the files over in batches. Reads names only. `isCancelled` is
    /// asked before each folder; a cancelled walk delivers what it has and stops.
    public static func enumerate(roots: [URL], isCancelled: () -> Bool, batchSize: Int = 500,
                                 deliver: ([Candidate]) -> Void) {
        var batch: [Candidate] = []
        func flush() { if !batch.isEmpty { deliver(batch); batch = [] } }
        func walk(_ dir: URL, trail: [String]) {
            guard !isCancelled(), let entries = LibraryListing.read(dir) else { return }
            let crumb = trail.joined(separator: " \u{203A} ")
            for e in entries where !e.isDirectory {
                let url = dir.appending(path: e.name)
                batch.append(Candidate(path: url.path, fileName: e.name, breadcrumb: crumb))
            }
            if batch.count >= batchSize { flush() }
            for e in entries where e.isDirectory { walk(dir.appending(path: e.name), trail: trail + [e.name]) }
        }
        for root in roots where !isCancelled() { walk(root, trail: [root.lastPathComponent]) }
        flush()
    }
}
