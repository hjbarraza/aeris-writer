import AppKit
import MarkdownCore

/// Live styling of the Markdown *source*: attribute changes only (font, color,
/// strikethrough), never characters. Attribute changes made straight on the text
/// storage register no undo, so styling never dirties the document.
///
/// On each character edit the enclosing top-level block is restyled at once (parsed
/// on its own, which is fast), then a debounced full parse runs off the main thread
/// and restyles what it changed, fixing anything wider than a block (a fence
/// opened or closed by the edit). Only the region where the new spans differ from
/// the last full pass's (plus everything restyled locally since) is re-applied, so
/// TextKit 2 keeps the layout of the rest.
@MainActor
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    private let storage: NSTextStorage
    /// Bumped on every character edit; a background parse applies only if unchanged.
    private var generation = 0
    private var pending: DispatchWorkItem?

    /// Text size multiplier (View ▸ Bigger / Smaller). Every font the styler sets is
    /// scaled by it, so headings keep their proportion to body text.
    private(set) var scale: CGFloat

    /// The spans of the last full pass, in the text as it was then.
    private var applied: [StyleSpan] = []
    /// Since the last full pass: the union of everything restyled locally (in
    /// today's offsets) and the net change in length. Every edit lies inside `dirty`.
    private var dirty: NSRange?
    private var delta = 0
    /// Line starts of the top-level blocks in the last full pass (same text as
    /// `applied`): where a parse of today's text can begin with nothing open, as
    /// long as it is before every edit since.
    private var blockStarts: [Int] = [0]
    /// A text-size re-application is still going through its slices.
    private var slicing = false
    /// The next full pass re-applies everything (after a scale change).
    private var restyleAllNext = false
    /// Called after each full pass: what depends on code-block marking can re-check
    /// (the per-edit block restyle can't see a fence that spans blank lines).
    var didApplyFullPass: (() -> Void)?

    static func baseFont(scale: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 15 * scale, weight: .regular)
    }
    private var baseFont: NSFont { Self.baseFont(scale: scale) }
    private var base: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor]
    }
    /// Marks code-block text so an edit inside a block isn't restyled as prose.
    private static let codeBlockKey = NSAttributedString.Key("AerisCodeBlock")

    init(storage: NSTextStorage, scale: CGFloat = 1) {
        self.storage = storage
        self.scale = scale
        super.init()
        storage.delegate = self
        restyleAll()
    }

    private func restyleAll() {
        let all = NSRange(location: 0, length: storage.length)
        (applied, blockStarts) = MarkdownCore.styleSpansAndBlockStarts(storage.string)
        dirty = nil
        delta = 0
        storage.beginEditing()
        apply(applied, in: all, offset: 0)
        storage.endEditing()
    }

    /// A new text size: the blocks around `visible` take it at once; the rest
    /// follows with a full pass parsed off the main thread.
    func setScale(_ newScale: CGFloat, visible: NSRange) {
        guard newScale != scale else { return }
        scale = newScale
        let ns = storage.string as NSString
        let block = blockRange(around: NSIntersectionRange(visible, NSRange(location: 0, length: ns.length)), in: ns)
        storage.beginEditing()
        apply(MarkdownCore.styleSpans(ns.substring(with: block)), in: block, offset: block.location)
        storage.endEditing()
        // Parsed on its own, the block may have lost code marking it has in the document.
        dirty = dirty.map { NSUnionRange($0, block) } ?? block
        restyleAllNext = true
        pending?.cancel()
        startFullParse()
    }

    /// Whether `index` is in a code block (fenced or indented), as last styled.
    func isCodeBlock(at index: Int) -> Bool {
        index >= 0 && index < storage.length && storage.attribute(Self.codeBlockKey, at: index, effectiveRange: nil) != nil
    }

    /// Whether `index` is in a code block in today's text. The code marking answers
    /// when it is current there: no edit since the last full pass at or before
    /// `index`'s line (a line's code status depends only on the text up to it).
    /// Otherwise the text is parsed from the last top-level block start before
    /// every edit, to the end of `index`'s run of non-blank lines.
    func isInCode(at index: Int) -> Bool {
        let ns = storage.string as NSString
        let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: min(max(index, 0), ns.length), length: 0)))
        if !slicing, dirty.map({ lineEnd <= $0.location }) ?? true { return isCodeBlock(at: index) }
        return MarkdownCore.isInCodeBlock(storage.string, at: index, parseFrom: freshParseStart(before: index))
    }

    /// A restart point of today's text at or before `index` (see
    /// `MarkdownCore.isRestartPoint`): where a parse can start and agree with the
    /// whole document's. Before every edit since the last full pass, the last
    /// pass's restart points still hold. After the edits they hold shifted, once
    /// the parse is back in step: the first one past the edits is checked (one
    /// parse of the edited block, once per text version); otherwise the last one
    /// before the edits is used.
    func freshParseStart(before index: Int) -> Int {
        guard let d = dirty else { return lastRestart(atOrBefore: index) }
        // A restart point holds only if its whole line is unedited (an edited
        // fence line may no longer open anything): stay before the first edited line.
        let ns = storage.string as NSString
        let firstEditedLine = ns.lineRange(for: NSRange(location: min(d.location, ns.length), length: 0)).location
        let before = lastRestart(atOrBefore: min(firstEditedLine - 1, index))
        let oldEnd = NSMaxRange(d) - delta
        guard index >= NSMaxRange(d), let first = blockStarts.first(where: { $0 >= oldEnd }),
              first + delta <= index, resyncs(at: first + delta, from: before) else { return before }
        return lastRestart(atOrBefore: index - delta) + delta
    }

    private func lastRestart(atOrBefore limit: Int) -> Int {
        var lo = 0, hi = blockStarts.count - 1, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if blockStarts[mid] <= limit { best = blockStarts[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }

    /// Whether `point` is still a restart point of today's text; cached per text version.
    private func resyncs(at point: Int, from start: Int) -> Bool {
        if let r = resync, r.generation == generation, r.point == point, r.start == start { return r.ok }
        let ok = MarkdownCore.isRestartPoint(storage.string, point, parseFrom: start)
        resync = (generation, point, start, ok)
        return ok
    }
    private var resync: (generation: Int, point: Int, start: Int, ok: Bool)?

    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        // Our own attribute changes come back here as .editedAttributes; ignore them.
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated { charactersEdited(editedRange, change: delta) }
    }

    private func charactersEdited(_ editedRange: NSRange, change: Int) {
        generation += 1
        // Already inside processEditing: no begin/endEditing here.
        let restyled: NSRange
        if isInsideCodeBlock(editedRange) {
            // New text inside a code block just takes the code look; the block's
            // own text was there before the edit and is already styled.
            storage.setAttributes(base, range: editedRange)
            styleCode(editedRange)
            restyled = editedRange
        } else {
            let ns = storage.string as NSString
            restyled = blockRange(around: editedRange, in: ns)
            apply(MarkdownCore.styleSpans(ns.substring(with: restyled)), in: restyled, offset: restyled.location)
        }
        noteEdit(editedRange, change: change, restyled: restyled)
        scheduleFullRestyle()
    }

    /// Moves `dirty` through an edit (old text `edited.length - change` long at
    /// `edited.location`, now `edited`) and adds what was just restyled.
    private func noteEdit(_ edited: NSRange, change: Int, restyled: NSRange) {
        delta += change
        guard let d = dirty else { dirty = restyled; return }
        let oldEnd = NSMaxRange(edited) - change
        func map(_ x: Int, inside: Int) -> Int { x <= edited.location ? x : x >= oldEnd ? x + change : inside }
        let a = map(d.location, inside: edited.location), b = map(NSMaxRange(d), inside: NSMaxRange(edited))
        dirty = NSUnionRange(NSRange(location: a, length: max(b - a, 0)), restyled)
    }

    /// Inside a code block when the untouched characters on both sides of the edit
    /// are code (the end of the document counts as code: an open fence runs to it).
    private func isInsideCodeBlock(_ edited: NSRange) -> Bool {
        let before = edited.location - 1, after = NSMaxRange(edited)
        func isCode(_ i: Int) -> Bool { storage.attribute(Self.codeBlockKey, at: i, effectiveRange: nil) != nil }
        return before >= 0 && isCode(before) && (after >= storage.length || isCode(after))
    }

    /// The top-level block around the edit, so context-dependent lines (nested list
    /// items, continuation paragraphs, setext underlines, lazy quote lines) parse as
    /// they do in the whole document. A block starts at a column-0 line after a blank
    /// line (or the start) and ends before a blank line followed by a column-0 line
    /// (or the end). Huge blocks fall back to the paragraph; the full pass follows.
    private func blockRange(around edited: NSRange, in ns: NSString) -> NSRange {
        let cap = 20_000
        func line(at i: Int) -> NSRange { ns.lineRange(for: NSRange(location: i, length: 0)) }
        func isBlank(_ r: NSRange) -> Bool {
            ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func startsAtColumn0(_ r: NSRange) -> Bool {
            guard r.length > 0 else { return false }
            let c = ns.character(at: r.location)
            return !(c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D)
        }
        var lo = line(at: edited.location)
        while lo.location > 0 {
            let prev = line(at: lo.location - 1)
            if startsAtColumn0(lo) && isBlank(prev) { break }
            lo = prev
            if edited.location - lo.location > cap { return ns.paragraphRange(for: edited) }
        }
        var hi = NSMaxRange(line(at: NSMaxRange(edited)))
        while hi < ns.length {
            let next = line(at: hi)
            if isBlank(next), NSMaxRange(next) >= ns.length || startsAtColumn0(line(at: NSMaxRange(next))) { break }
            hi = NSMaxRange(next)
            if hi - NSMaxRange(edited) > cap { return ns.paragraphRange(for: edited) }
        }
        return NSRange(location: lo.location, length: hi - lo.location)
    }

    private func scheduleFullRestyle() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startFullParse() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// At most one full parse in flight. A request while one runs is remembered and
    /// served, once, with the latest text when the running parse finishes.
    private var parsing = false
    private var parseRequested = false

    private func startFullParse() {
        guard !parsing else { parseRequested = true; return }
        parsing = true
        let gen = generation
        let text = storage.string
        Task { [weak self] in
            let (spans, starts) = await Task.detached(priority: .userInitiated) {
                MarkdownCore.styleSpansAndBlockStarts(text)
            }.value
            guard let self else { return }
            self.parsing = false
            if gen == self.generation {
                self.applyFullPass(spans, blockStarts: starts)
                self.didApplyFullPass?()
            }
            // Re-parse only if the text moved on since this parse's snapshot.
            if self.parseRequested, gen != self.generation {
                self.startFullParse()
            }
            self.parseRequested = false
        }
    }

    /// Applies a full pass's spans where they differ from the last pass's, plus
    /// where text was restyled locally since. Outside that region every character
    /// is covered by the same spans as before, so its attributes are already right.
    private func applyFullPass(_ spans: [StyleSpan], blockStarts starts: [Int]) {
        let all = NSRange(location: 0, length: storage.length)
        defer { applied = spans; blockStarts = starts; dirty = nil; delta = 0; restyleAllNext = false }
        if restyleAllNext {
            applyInSlices(spans, from: 0, generation: generation)
            return
        }
        // Old spans in today's offsets: unchanged before `dirty`, shifted after it;
        // one reaching into it is widened to cover its side of `dirty`.
        let d = dirty ?? NSRange(location: all.length, length: 0)
        let oldEnd = NSMaxRange(d) - delta
        func moved(_ s: StyleSpan) -> NSRange {
            let a = s.range.location, b = NSMaxRange(s.range)
            let na = a < d.location ? a : a >= oldEnd ? a + delta : d.location
            let nb = b <= d.location ? b : b >= oldEnd ? b + delta : NSMaxRange(d)
            return NSRange(location: na, length: max(nb - na, 0))
        }
        func same(_ old: StyleSpan, _ new: StyleSpan) -> Bool { old.kind == new.kind && moved(old) == new.range }
        // Matching runs from the front and from the back; what is left between differs.
        var i = 0, j = 0
        while i < applied.count, i < spans.count, same(applied[i], spans[i]) { i += 1 }
        while j < applied.count - i, j < spans.count - i,
              same(applied[applied.count - 1 - j], spans[spans.count - 1 - j]) { j += 1 }
        var region = dirty
        for s in applied[i..<(applied.count - j)] { region = region.map { NSUnionRange($0, moved(s)) } ?? moved(s) }
        for s in spans[i..<(spans.count - j)] { region = region.map { NSUnionRange($0, s.range) } ?? s.range }
        guard let region else { return }
        let r = NSIntersectionRange(region, all)
        guard r.length > 0 else { return }
        storage.beginEditing()
        apply(spans, in: r, offset: 0)
        storage.endEditing()
    }

    /// Re-applies everything (a new text size), one slice per main-queue turn so
    /// typing and scrolling stay responsive. An edit midway leaves the rest to the
    /// full pass that edit schedules.
    private func applyInSlices(_ spans: [StyleSpan], from start: Int, generation gen: Int) {
        guard gen == generation else {
            // An edit came first: the next full pass redoes everything; until then
            // no code marking is trusted.
            restyleAllNext = true
            slicing = false
            dirty = NSRange(location: 0, length: storage.length)
            return
        }
        let ns = storage.string as NSString
        var end = min(start + 20_000, ns.length)
        if end < ns.length { end = max(ns.rangeOfComposedCharacterSequence(at: end).location, start + 1) }
        storage.beginEditing()
        apply(spans, in: NSRange(location: start, length: end - start), offset: 0)
        storage.endEditing()
        slicing = end < ns.length
        guard slicing else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyInSlices(spans, from: end, generation: gen) }
        }
    }

    /// Reset `range` to the base look, then layer the spans that reach into it,
    /// clipped to it (parents before children, so a child's color wins and traits
    /// accumulate). `offset` shifts span ranges.
    private func apply(_ spans: [StyleSpan], in range: NSRange, offset: Int) {
        storage.setAttributes(base, range: range)
        for span in spans {
            let r = NSIntersectionRange(NSRange(location: span.range.location + offset, length: span.range.length), range)
            guard r.length > 0 else { continue }
            switch span.kind {
            case .heading(let level):
                let size: CGFloat = level == 1 ? 22 : level == 2 ? 19 : level == 3 ? 17 : 15
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size * scale, weight: .bold), range: r)
            case .strong: addTrait(.bold, in: r)
            case .emphasis: addTrait(.italic, in: r)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .inlineCode: color(.secondaryLabelColor, r)
            case .codeBlock: styleCode(r)
            case .link: color(.linkColor, r)
            case .blockQuote: color(.secondaryLabelColor, r)
            case .syntax, .listMarker: color(.tertiaryLabelColor, r)
            case .image, .thematicBreak: break
            }
        }
    }

    private func styleCode(_ r: NSRange) {
        color(.secondaryLabelColor, r)
        storage.addAttribute(Self.codeBlockKey, value: true, range: r)
    }

    private func color(_ c: NSColor, _ r: NSRange) {
        storage.addAttribute(.foregroundColor, value: c, range: r)
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, in r: NSRange) {
        storage.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = value as? NSFont ?? baseFont
            let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            storage.addAttribute(.font, value: NSFont(descriptor: d, size: font.pointSize) ?? font, range: sub)
        }
    }
}
