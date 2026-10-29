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

    /// A flag one thread sets and another reads, to stop a walk.
    public final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        public init() {}
        public func cancel() { lock.withLock { flag = true } }
        public var isCancelled: Bool { lock.withLock { flag } }
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

    // MARK: Inside files

    /// Files larger than this are not searched.
    public static let maxFileBytes = 2_000_000

    /// One place a query occurs inside a file.
    public struct ContentMatch: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case heading(level: Int), text }
        public let kind: Kind
        /// 1-based line number.
        public let line: Int
        /// The match in the file's text, in UTF-16 units (an `NSRange` into the text).
        public let range: NSRange
        /// The heading's title, or the line (trimmed; cut around the match when long).
        public let snippet: String
        /// Character offsets of the match inside `snippet`.
        public let highlight: Range<Int>
    }

    /// The matches found in one file, headings first, then text, each in document order.
    public struct FileHits: Equatable, Sendable {
        public let candidate: Candidate
        public let matches: [ContentMatch]
    }

    /// Occurrences of `query` (case and accents ignored, as one phrase) in `text`, one per line,
    /// at most `maxFound`. A heading is an ATX `#` line outside a code fence; heading lines only
    /// ever give heading results, every other line only text results. Headings come first.
    public static func search(in text: String, query: String, headings wantHeadings: Bool, text wantText: Bool,
                              maxFound: Int) -> [ContentMatch] {
        let q = Array(query.trimmingCharacters(in: .whitespaces).map(fold))
        guard !q.isEmpty, wantHeadings || wantText, maxFound > 0 else { return [] }
        var headings: [ContentMatch] = [], texts: [ContentMatch] = []
        var fence: Character?
        var lineNumber = 0
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { sub, subRange, _, stop in
            guard let line = sub else { return }
            lineNumber += 1
            let chars = Array(line)
            let lead = chars.prefix { $0 == " " }.count
            if lead <= 3, let f = chars.dropFirst(lead).first, f == "`" || f == "~",
               chars.dropFirst(lead).prefix(3).filter({ $0 == f }).count == 3 {
                if fence == nil { fence = f } else if fence == f { fence = nil }
            }
            var kind = ContentMatch.Kind.text
            var from = 0, to = chars.count     // the part of the line that is searched
            if fence == nil, lead <= 3, let h = headingParts(chars, lead: lead) {
                guard wantHeadings else { return }
                kind = .heading(level: h.level); from = h.start; to = h.end
            } else if !wantText { return }
            guard let i = indexOf(q, in: chars[from..<to].map(fold)) else { return }
            let start = from + i
            let location = subRange.location + String(chars[..<start]).utf16.count
            let length = String(chars[start..<start + q.count]).utf16.count
            let snippet: String, highlight: Range<Int>
            if case .heading = kind {
                snippet = String(chars[from..<to]); highlight = i..<i + q.count
            } else {
                (snippet, highlight) = snippetAround(chars, start: start, length: q.count)
            }
            let m = ContentMatch(kind: kind, line: lineNumber, range: NSRange(location: location, length: length),
                                 snippet: snippet, highlight: highlight)
            if case .heading = kind { headings.append(m) } else { texts.append(m) }
            if headings.count + texts.count >= maxFound { stop.pointee = true }
        }
        return headings + texts
    }

    /// An ATX heading line: its level and the title's span in `chars`.
    private static func headingParts(_ chars: [Character], lead: Int) -> (level: Int, start: Int, end: Int)? {
        let hashes = chars.dropFirst(lead).prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        var start = lead + hashes
        guard start == chars.count || chars[start] == " " || chars[start] == "\t" else { return nil }
        var end = chars.count
        while start < end, chars[start] == " " || chars[start] == "\t" { start += 1 }
        while end > start, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
        var closing = end
        while closing > start, chars[closing - 1] == "#" { closing -= 1 }
        if closing < end, closing == start || chars[closing - 1] == " " || chars[closing - 1] == "\t" {
            end = closing
            while end > start, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
        }
        return start < end ? (hashes, start, end) : nil
    }

    private static func indexOf(_ q: [Character], in text: [Character]) -> Int? {
        guard q.count <= text.count else { return nil }
        for i in 0...(text.count - q.count) where text[i..<i + q.count].elementsEqual(q) { return i }
        return nil
    }

    /// The line trimmed, and cut to a window around the match when it is long.
    private static func snippetAround(_ chars: [Character], start: Int, length: Int) -> (String, Range<Int>) {
        var lo = 0, hi = chars.count
        while lo < start, chars[lo] == " " || chars[lo] == "\t" { lo += 1 }
        while hi > start + length, chars[hi - 1] == " " || chars[hi - 1] == "\t" { hi -= 1 }
        var cutHead = false, cutTail = false
        if hi - lo > 80 {
            let want = max(lo, start - 30)
            if want > lo { lo = want; cutHead = true }
            if hi - lo > 80 { hi = lo + max(80, start - lo + length); cutTail = true }
        }
        let head = cutHead ? "\u{2026}" : ""
        let offset = head.count + start - lo
        return (head + String(chars[lo..<hi]) + (cutTail ? "\u{2026}" : ""), offset..<offset + length)
    }

    /// The file's bytes, or nil when it is unreadable or over `maxFileBytes`.
    public static func readIfSmall(_ path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Searches `candidates` in order, handing over each file that has matches, until `maxFiles`
    /// files were delivered. `read` gives a file's text (nil skips it). `isCancelled` is asked
    /// before each file.
    public static func searchFiles(query: String, candidates: [Candidate], headings: Bool, text: Bool, maxFiles: Int,
                                   maxPerFile: Int = 100, read: (Candidate) -> String?, isCancelled: () -> Bool,
                                   deliver: (FileHits) -> Void) {
        var delivered = 0
        for cand in candidates {
            if isCancelled() || delivered >= maxFiles { return }
            guard let body = read(cand) else { continue }
            let found = search(in: body, query: query, headings: headings, text: text, maxFound: maxPerFile)
            if !found.isEmpty { deliver(FileHits(candidate: cand, matches: found)); delivered += 1 }
        }
    }
}
