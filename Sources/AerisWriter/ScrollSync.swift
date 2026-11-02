import AppKit
import MarkdownCore

/// Editor drives preview: as the editor scrolls, the preview scrolls to the same
/// source line (throttled to ~30 Hz). One direction only.
@MainActor final class ScrollSync {
    private let textView: NSTextView
    private let preview: PreviewViewController
    private var lines: SourceLines?
    private var pending = false
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []  // only touched in init and deinit

    init(textView: NSTextView, preview: PreviewViewController) {
        self.textView = textView
        self.preview = preview
        guard let clip = textView.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.schedule() } })
        // TextKit 2 re-estimates heights as it lays out, which resizes the text view and
        // can move which line is at the top without a scroll; follow that too.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.schedule() } })
        if let storage = textView.textStorage {
            // Line starts are cached per text version: drop them when characters change.
            // Re-sync too: an edit can shift which line sits at the top without a scroll.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
            ) { [weak self] note in
                let textChanged = (note.object as? NSTextStorage)?
                    .editedMask.contains(.editedCharacters) ?? false
                guard textChanged else { return }
                MainActor.assumeIsolated { self?.lines = nil; self?.schedule() }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func schedule() {
        guard !pending else { return }
        pending = true
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                self.preview.scroll(toSourceLine: self.lineAtTop())
            }
        }
    }

    /// Fractional 1-based source line at the top of the editor's visible rect:
    /// the line of the layout fragment (paragraph) there, plus how far into it the
    /// top edge falls. 0 when scrolled to the very top.
    func lineAtTop() -> Double {
        let top = textView.visibleRect.minY
        guard top > 0, let tlm = textView.textLayoutManager,
              let tcm = tlm.textContentManager else { return 0 }
        let y = max(top - textView.textContainerOrigin.y, 0)
        guard let fragment = tlm.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return 0 }
        let offset = tcm.offset(from: tcm.documentRange.location, to: fragment.rangeInElement.location)
        if lines == nil { lines = SourceLines(textView.string) }
        let frame = fragment.layoutFragmentFrame
        let into = frame.height > 0 ? min(max((y - frame.minY) / frame.height, 0), 1) : 0
        return Double(lines!.line(at: offset)) + into
    }
}
