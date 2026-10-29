import AppKit
import MarkdownCore

/// Owns the editor's scroll view + NSTextView. The text view edits the document's
/// own `textStorage` (no copy), so a revert or reload shows up in the view at once.
/// Edits register undo on the document's undo manager, which is what marks the
/// document dirty, so undo and the edited state always agree.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSMenuItemValidation,
    NSGestureRecognizerDelegate {
    private var textView: NSTextView!
    private(set) var styler: MarkdownStyler?

    weak var document: MarkdownDocument? {
        didSet {
            document?.editor = self
            guard let storage = document?.textStorage else { return }
            // Typing in this document never joins an undo group of the previous one.
            textView.breakUndoCoalescing()
            textView.textContentStorage?.textStorage = storage
            // The previous document's caret means nothing here.
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            // The file's text arrives without attributes; the styler gives it the
            // editor's look and keeps it styled as it changes.
            styler = MarkdownStyler(storage: storage, scale: textScale)
            styler?.didApplyFullPass = { [weak self] in
                if self?.completion.isVisible == true { self?.updateCompletion(typed: false) }
            }
            // Swapped into a window already on screen (opened from the library): nothing of
            // the previous document stays. Before the first appearance, viewDidAppear restores.
            if restoredState {
                dismissedTrigger = nil
                ownTags = nil
                hideCompletion()
                textView.scroll(.zero)
                textReloaded()
                restoreOrPlaceAtEnd(document?.savedState)
            }
        }
    }

    #if DEBUG
    var textViewForTesting: NSTextView { textView }
    #endif

    /// Moves the keyboard to the text.
    func focusText() {
        view.window?.makeFirstResponder(textView)
    }

    /// Puts the caret on `range` (clamped to the text) and scrolls it into view.
    func select(_ range: NSRange) {
        let length = (textView.string as NSString).length
        let location = min(max(range.location, 0), length)
        textView.setSelectedRange(NSRange(location: location, length: min(max(range.length, 0), length - location)))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Opens the find bar with its replace field, searching for `query` (the find pasteboard is
    /// what the bar reads, as with the system's own Find).
    func showFindAndReplace(query: String) {
        textView.usesFindBar = true
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(query, forType: .string)
        focusText()
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        textView.performTextFinderAction(item)
    }

    override func loadView() {
        // What NSTextView.scrollableTextView() builds, with a text view that can take over Paste.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let editorView = EditorTextView(usingTextLayoutManager: true)
        editorView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        editorView.maxSize = NSSize(width: 10_000_000, height: 10_000_000)
        editorView.isVerticallyResizable = true
        editorView.autoresizingMask = [.width, .height]
        editorView.usesRuler = false
        editorView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: 10_000_000)
        scroll.documentView = editorView
        editorView.richPaste = { [weak self] in self?.pasteRichTextIfSet() ?? false }
        textView = editorView
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = Self.inset
        // Soft-wrap: the text container follows the view's width.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        let click = NSClickGestureRecognizer(target: self, action: #selector(checkboxClicked(_:)))
        click.delegate = self
        textView.addGestureRecognizer(click)
        view = scroll
        loadViewSettings()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        document?.undoManager
    }

    // MARK: Format commands (menu items carry a MarkdownElement)

    @objc func toggleInline(_ sender: NSMenuItem) { perform(sender) }
    @objc func toggleBlock(_ sender: NSMenuItem) { perform(sender) }

    /// Never during IME composition: the edit would commit the marked text.
    private func perform(_ sender: NSMenuItem) {
        guard !textView.hasMarkedText(), let element = sender.representedObject as? MarkdownElement,
              let edit = element.edit(text: textView.string, selection: textView.selectedRange(),
                                      parseFrom: parseStart()) else { return }
        apply(edit, undoName: element.undoName)
    }

    /// The Format and View commands. The window controller routes them here even
    /// when the preview has focus (it is not in the editor's responder chain).
    static let commandActions: Set<Selector> = [
        #selector(toggleInline(_:)), #selector(toggleBlock(_:)),
        #selector(toggleTypewriterMode(_:)), #selector(toggleFocusMode(_:)), #selector(setFocusScope(_:)),
        #selector(makeTextBigger(_:)), #selector(makeTextSmaller(_:)), #selector(makeTextActualSize(_:)),
    ]

    // MARK: Paste as Markdown (M1.5-25)

    /// Edit > Paste as Markdown: the pasteboard's rich text as Markdown; a pasteboard without
    /// convertible rich text pastes as plain text, exactly as Paste does.
    @objc func pasteAsMarkdown(_ sender: Any?) {
        if !pasteMarkdown(from: .general) { (textView as? EditorTextView)?.pasteWithoutRichText(sender) }
    }

    /// Edit > Paste Rich Text as Markdown: makes plain Paste (⌘V) do the same for rich sources.
    @objc func togglePasteRichTextAsMarkdown(_ sender: Any?) {
        Self.defaults.set(!Self.defaults.bool(forKey: DefaultsKey.pasteRichAsMarkdown),
                          forKey: DefaultsKey.pasteRichAsMarkdown)
    }

    /// Called by Paste; true when it handled the paste.
    fileprivate func pasteRichTextIfSet() -> Bool {
        Self.defaults.bool(forKey: DefaultsKey.pasteRichAsMarkdown) && pasteMarkdown(from: .general, emphasisCounts: false)
    }

    /// Replaces the selection with the pasteboard's rich text as Markdown, in the document's
    /// line ending, as one undo step. False (nothing changed) when there is no rich text
    /// with structure to convert, or the text view is not editable or is composing.
    @discardableResult
    func pasteMarkdown(from board: NSPasteboard, emphasisCounts: Bool = true) -> Bool {
        guard textView.isEditable, !textView.hasMarkedText(),
              let markdown = Self.markdown(from: board, emphasisCounts: emphasisCounts) else { return false }
        let text = LineEnding.convert(markdown, to: LineEnding.of(textView.string))
        let range = textView.selectedRange()
        return apply(TextEdit(range: range, replacement: text,
                              selection: NSRange(location: range.location + (text as NSString).length, length: 0)),
                     undoName: "Paste")
    }

    /// The pasteboard's HTML (or RTF, via Cocoa's HTML export) as Markdown; nil if none.
    static func markdown(from board: NSPasteboard, emphasisCounts: Bool = true) -> String? {
        var html: String?
        if let data = board.data(forType: .html) {
            guard data.count <= RichTextMarkdown.maxHTMLBytes else { return nil }
            html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
        } else if let data = board.data(forType: .rtf), data.count <= RichTextMarkdown.maxHTMLBytes,
                  let attributed = NSAttributedString(rtf: data, documentAttributes: nil),
                  let out = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            html = String(data: out, encoding: .utf8)
        }
        return html.flatMap { RichTextMarkdown.convert(html: $0, emphasisCounts: emphasisCounts) }
    }

    // MARK: Copy matrix (M3-4)

    enum CopyFormat { case markdown, html, richText, plainText }

    @objc func copyAsMarkdown(_ sender: Any?) { copy(as: .markdown, to: .general) }
    @objc func copyAsHTML(_ sender: Any?) { copy(as: .html, to: .general) }
    @objc func copyAsRichText(_ sender: Any?) { copy(as: .richText, to: .general) }
    @objc func copyAsPlainText(_ sender: Any?) { copy(as: .plainText, to: .general) }

    /// The selection's Markdown (every range of a discontiguous selection, joined by the document's
    /// line ending, as stock Copy does), or the whole document when nothing is selected.
    func copySource() -> String {
        let text = textView.string as NSString
        let parts = textView.selectedRanges.map(\.rangeValue)
            .filter { $0.length > 0 && NSMaxRange($0) <= text.length }.map { text.substring(with: $0) }
        return parts.isEmpty ? text as String : parts.joined(separator: LineEnding.of(text as String))
    }

    /// Above this many UTF-16 units of source, Copy as Rich Text builds off the main thread.
    static let richTextAsyncThreshold = 300_000

    /// The RTF of Markdown `source`: HTML without front matter or resources, through Cocoa's importer.
    nonisolated static func richTextData(_ source: String) -> (rtf: Data, plain: String)? {
        let body = RichTextHTML.withoutResources(MarkdownCore.html(String(Excerpt.withoutFrontMatter(Substring(source)))))
        let page = "<html><head><meta charset=\"utf-8\"><style>body { font-family: -apple-system, Helvetica; font-size: 13px; }"
            + " code, pre { font-family: Menlo; }</style></head><body>\(body)</body></html>"
        guard let attributed = NSAttributedString(html: Data(page.utf8), options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
              let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
        else { return nil }
        return (rtf, attributed.string)
    }

    /// Puts the selection (or the whole document) on `board` in one format: only that type,
    /// plus plain text. Never touches the document. Front matter is left out of HTML, Rich Text and
    /// Plain Text (Markdown stays raw). A large Rich Text copy puts the plain text on at once and the
    /// RTF when it is built (if the pasteboard has not changed since); `done` runs then.
    @discardableResult
    func copy(as format: CopyFormat, to board: NSPasteboard, done: (() -> Void)? = nil) -> Bool {
        let source = copySource()
        board.clearContents()
        switch format {
        case .markdown:
            return board.setString(source, forType: .string)
        case .plainText:
            return board.setString(PlainText.make(source), forType: .string)
        case .html:
            let html = MarkdownCore.html(String(Excerpt.withoutFrontMatter(Substring(source))))
            return board.setData(Data(html.utf8), forType: .html) && board.setString(html, forType: .string)
        case .richText:
            if (source as NSString).length > Self.richTextAsyncThreshold {
                guard board.setString(PlainText.make(source), forType: .string) else { return false }
                let count = board.changeCount
                nonisolated(unsafe) let target = board, finish = done
                // NSAttributedString(html:) is main-thread only: build it on the next main-queue turn,
                // after the menu has closed and the plain text is already on the pasteboard.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let built = Self.richTextData(source)
                        if let built, target.changeCount == count { target.setData(built.rtf, forType: .rtf) }
                        finish?()
                    }
                }
                return true
            }
            guard let built = Self.richTextData(source) else { return false }
            return board.setData(built.rtf, forType: .rtf) && board.setString(built.plain, forType: .string)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copyAsMarkdown(_:)), #selector(copyAsHTML(_:)), #selector(copyAsRichText(_:)),
             #selector(copyAsPlainText(_:)): return textView.string.contains { !$0.isWhitespace }
        case #selector(toggleTypewriterMode(_:)): item.state = typewriter ? .on : .off; return true
        case #selector(toggleFocusMode(_:)): item.state = focus ? .on : .off; return true
        case #selector(setFocusScope(_:)): item.state = item.tag == focusScope.rawValue ? .on : .off; return true
        case #selector(togglePasteRichTextAsMarkdown(_:)):
            item.state = Self.defaults.bool(forKey: DefaultsKey.pasteRichAsMarkdown) ? .on : .off; return true
        case #selector(pasteAsMarkdown(_:)): return textView.isEditable && !textView.hasMarkedText()
        case #selector(makeTextBigger(_:)): return textSizeStep < Self.textSizeSteps.upperBound
        case #selector(makeTextSmaller(_:)): return textSizeStep > Self.textSizeSteps.lowerBound
        case #selector(makeTextActualSize(_:)): return textSizeStep != 0
        default: break
        }
        guard let element = item.representedObject as? MarkdownElement else { return true }
        // Cheap: AppKit validates every item on each key equivalent, so no edit is
        // computed here (that happens when the command runs).
        return textView.isEditable && !textView.hasMarkedText()
            && element.mayApply(text: textView.string, selection: textView.selectedRange())
    }

    /// The only way commands change the text: one undoable change through the text
    /// view, so undo, the edited state, the styler and the preview all see it.
    /// Undo puts back the selection from before the edit, redo the one after it.
    /// An edit that changes nothing only moves the selection.
    /// Returns false when the text view refused the edit (the text is unchanged).
    @discardableResult
    private func apply(_ edit: TextEdit, undoName: String) -> Bool {
        let storage = textView.textStorage!
        var applied = true
        if storage.attributedSubstring(from: edit.range).string != edit.replacement {
            guard textView.isEditable else { return false }
            let undo = textView.undoManager
            textView.breakUndoCoalescing()
            undo?.beginUndoGrouping()
            registerSelection(undo, set: textView.selectedRange(), inverse: nil)
            applyingEdit = true
            defer { applyingEdit = false }
            if textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                storage.beginEditing()
                storage.replaceCharacters(in: edit.range, with: edit.replacement)
                storage.endEditing()
                textView.didChangeText()
                registerSelection(undo, set: nil, inverse: edit.selection)
            } else {
                applied = false
            }
            undo?.setActionName(undoName)
            undo?.endUndoGrouping()
        }
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        return applied
    }

    /// Replaces the whole text as one undoable edit (reloading the file), keeping the
    /// selection's offsets, clamped to the new text. False when the text view refused it.
    func replaceAllText(with text: String, undoName: String) -> Bool {
        let sel = textView.selectedRange(), length = (text as NSString).length
        let location = min(sel.location, length)
        return apply(TextEdit(range: NSRange(location: 0, length: (textView.string as NSString).length), replacement: text,
                       selection: NSRange(location: location, length: min(sel.length, length - location))),
              undoName: undoName)
    }

    /// An undo step that selects `set` (if any) and registers its inverse, so the
    /// same step on the redo stack selects `inverse`. Registered before and after a
    /// text change, it runs after the text's own undo (and redo), which would
    /// otherwise leave the selection on the changed text.
    private func registerSelection(_ undo: UndoManager?, set: NSRange?, inverse: NSRange?) {
        undo?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                if let set {
                    let length = (editor.textView.string as NSString).length
                    let location = min(set.location, length)
                    editor.textView.setSelectedRange(NSRange(location: location, length: min(set.length, length - location)))
                    editor.textView.scrollRangeToVisible(editor.textView.selectedRange())
                }
                editor.registerSelection(undo, set: inverse, inverse: set)
            }
        }
    }

    // MARK: Line endings

    /// True while `apply` runs its edit: commands build their own line endings, and a
    /// reload's text is the file's, so neither is converted.
    private var applyingEdit = false

    /// Two jobs, each on a one-range change with one selection, never while `apply`
    /// runs or during IME composition:
    /// 1. Renumbering (M1.5-23): a deletion that removes a line break, outside code
    ///    blocks, in a sequential ordered list is replaced by `ListEdit.delete`'s edit
    ///    (the deletion plus the new numbers below it), one undo step named "Typing".
    ///    That covers Backspace/Delete and also Cut and Edit > Delete.
    /// 2. Line endings (M1-12):
    /// Typed, pasted and dropped text takes the document's line ending (its first one;
    /// LF if none), so a CRLF file never gains a lone LF. Existing text is never touched.
    /// Only a one-range change whose replaced text has no line break is converted. The
    /// trade: a change over several ranges (multiple selections, Replace All) or one that
    /// replaces existing breaks (Transformations, a paste over lines) goes in unconverted,
    /// because converting it could shift the other ranges or rewrite existing endings.
    /// Risking existing text is worse than an inserted lone LF.
    /// The converted insert is its own undo step.
    func textView(_ textView: NSTextView, shouldChangeTextInRanges ranges: [NSValue],
                  replacementStrings strings: [String]?) -> Bool {
        // 1. Renumbering after a deletion.
        if !applyingEdit, !textView.hasMarkedText(), ranges.count == 1, textView.selectedRanges.count == 1,
           strings == [""], !lineIsCode(at: ranges[0].rangeValue.location),
           let edit = ListEdit.delete(text: textView.string, range: ranges[0].rangeValue) {
            apply(edit, undoName: "Typing")
            return false
        }
        // 2. Line endings of inserted text.
        func hasBreak(_ s: String) -> Bool { s.utf16.contains { $0 == 0x0A || $0 == 0x0D } }
        // A paste over several selections arrives one range at a time, hence both counts.
        guard !applyingEdit, !textView.hasMarkedText(), ranges.count == 1, textView.selectedRanges.count == 1,
              let strings, strings.count == 1,
              hasBreak(strings[0]) else { return true }
        let range = ranges[0].rangeValue
        guard !hasBreak((textView.string as NSString).substring(with: range)) else { return true }
        let converted = LineEnding.convert(strings[0], to: LineEnding.of(textView.string))
        guard converted != strings[0] else { return true }
        textView.breakUndoCoalescing()
        textView.insertText(converted, replacementRange: range)
        textView.breakUndoCoalescing()
        return false
    }

    // MARK: Return / Tab / ⇧Tab in lists and tables

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        // While the completion list shows, these keys drive it instead.
        if completion.isVisible {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): completion.move(-1); return true
            case #selector(NSResponder.moveDown(_:)): completion.move(1); return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                acceptCompletion(); return true
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                dismissedTrigger = completionTrigger?.start
                hideCompletion(); return true
            default: break
            }
        }
        let text = textView.string, sel = textView.selectedRange()
        let edit: TextEdit?
        // In a code block, Return and Tab are plain text.
        if [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.insertBacktab(_:))].contains(selector), caretLineIsCode() { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            edit = ListEdit.newline(text: text, selection: sel)
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            let forward = selector == #selector(NSResponder.insertTab(_:))
            // A table-looking line is confirmed by a parse from a top-level start
            // (nil: not a top-level table, e.g. in code, HTML or a list item).
            let tableEdit = TableEdit.looksLikeTable(text: text, at: sel.location)
                ? (forward ? TableEdit.nextCell(in: text, at: sel.location, parseFrom: parseStart())
                           : TableEdit.previousCell(in: text, at: sel.location, parseFrom: parseStart()))
                : nil
            if let tableEdit {
                edit = tableEdit
            } else if ListEdit.isItem(text: text, selection: sel) {
                edit = forward ? ListEdit.indent(text: text, selection: sel)
                               : ListEdit.outdent(text: text, selection: sel)
            } else {
                edit = nil
            }
        default:
            edit = nil
        }
        guard let edit else { return false }
        apply(edit, undoName: "Typing")
        return true
    }

    /// The caret's line is in a code block (fenced or indented), as the styler last
    /// saw it: one attribute lookup, no parse.
    private func caretLineIsCode() -> Bool { lineIsCode(at: textView.selectedRange().location) }

    /// The line holding `location` is in a code block, as the styler last saw it.
    private func lineIsCode(at location: Int) -> Bool {
        let ns = textView.string as NSString
        var i = ns.lineRange(for: NSRange(location: location, length: 0)).location
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return styler?.isInCode(at: i) == true
    }

    /// Where a parse for the caret may start with nothing open (see TableEdit).
    private func parseStart() -> Int {
        styler?.freshParseStart(before: textView.selectedRange().location) ?? 0
    }

    // MARK: Autocomplete: #tags, [[wikilinks]], ](paths) from the document's folder

    /// The list under the caret; internal so the headless harness can read its model.
    let completion = CompletionPopup()
    /// The trigger the list is showing for, while it shows.
    private var completionTrigger: Completion.Trigger?
    /// A trigger dismissed with Esc stays closed until the caret leaves it.
    private var dismissedTrigger: Int?
    private var acceptingCompletion = false
    /// This document's tags minus the one being typed, read once per trigger (a
    /// whole-document parse), not on every keystroke.
    private var ownTags: (start: Int, tags: [String])?

    /// Typing opens or refilters the list; other edits and caret moves only refilter
    /// it, or close it once the caret has left the word it was opened for. Never
    /// during IME composition or with a selection.
    private func updateCompletion(typed: Bool) {
        let sel = textView.selectedRange()
        guard sel.length == 0, !textView.hasMarkedText(), let window = textView.window,
              let t = Completion.trigger(in: textView.string, caret: sel.location),
              styler?.isInCode(at: t.start) != true else {
            dismissedTrigger = nil
            ownTags = nil
            return hideCompletion()
        }
        guard t.start != dismissedTrigger, t.start == completionTrigger?.start || typed else {
            return hideCompletion()
        }
        dismissedTrigger = nil
        let prefix = (textView.string as NSString).substring(with: t.prefix)
        let items = Completion.rank(completionCandidates(for: t), prefix: prefix)
        guard !items.isEmpty else { return hideCompletion() }
        completionTrigger = t
        completion.onAccept = { [weak self] in self?.acceptCompletion() }
        let caret = textView.firstRect(forCharacterRange: NSRange(location: t.start, length: 0), actualRange: nil)
        completion.show(items, below: caret, in: window)
    }

    private func hideCompletion() {
        completionTrigger = nil
        completion.hide()
    }

    /// Tags from this document (minus the one being typed) and its folder's notes;
    /// notes or entries of the folder for wikilinks and paths. An untitled document
    /// has no folder: tags from itself only.
    private func completionCandidates(for t: Completion.Trigger) -> [String] {
        let own = document?.fileURL
        let folder = own?.deletingLastPathComponent()
        let snap = folder.flatMap { folder in
            FolderIndex.shared.snapshot(for: folder) { [weak self] in
                // The scan landed: refresh if the caret is still at this trigger.
                guard let self, Completion.trigger(in: self.textView.string,
                                                   caret: self.textView.selectedRange().location)?.start == t.start
                else { return }
                self.updateCompletion(typed: true)
            }
        }
        switch t.kind {
        case .hashtag:
            if ownTags?.start != t.start {
                let typed = NSRange(location: t.start, length: NSMaxRange(t.prefix) - t.start)
                ownTags = (t.start, Hashtags.extract((textView.string as NSString).replacingCharacters(in: typed, with: "")))
            }
            var tags = ownTags?.tags ?? []
            for (file, fileTags) in snap?.tagsByFile ?? [:] where file != own?.lastPathComponent { tags += fileTags }
            return tags
        case .wikilink:
            let ownName = own?.deletingPathExtension().lastPathComponent
            return (snap?.notes ?? []).filter { $0 != ownName }
        case .path:
            return snap?.entries ?? []
        }
    }

    private func acceptCompletion() {
        guard let t = completionTrigger, let value = completion.selected else { return }
        hideCompletion()
        acceptingCompletion = true
        defer { acceptingCompletion = false }
        apply(Completion.accept(value, for: t, in: textView.string), undoName: "Autocomplete")
    }

    // MARK: Task checkbox click in the source

    /// The recognizer only takes clicks that land on a task's `[ ]` / `[x]`, or ⌘-clicks on a
    /// link; every other click goes straight to the text view (selection, drags,
    /// double-clicks untouched). A taken click is consumed, so the text view never starts
    /// its own tracking.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        let point = textView.convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), linkURL(at: point) != nil { return true }
        return textView.isEditable && checkboxEdit(at: point) != nil
    }

    @objc func checkboxClicked(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended else { return }
        let point = sender.location(in: textView)
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true, let url = linkURL(at: point) {
            onLink?(url)
            return
        }
        guard let edit = checkboxEdit(at: point) else { return }
        apply(edit, undoName: "Toggle Task")
    }

    /// Opens a link ⌘-clicked in the source; set by the window controller.
    var onLink: ((URL) -> Void)?

    /// The link under `point` (text view coordinates), resolved against the document.
    func linkURL(at point: NSPoint) -> URL? {
        MarkdownCore.linkDestination(in: textView.string, at: textView.characterIndexForInsertion(at: point))
            .flatMap { LinkAction.resolve($0, documentURL: document?.fileURL) }
    }

    /// The checkbox toggle for a click at `point` (text view coordinates), if it hits one.
    func checkboxEdit(at point: NSPoint) -> TextEdit? {
        ListEdit.toggleCheckbox(text: textView.string, at: textView.characterIndexForInsertion(at: point))
    }

    // MARK: Caret + scroll state (persisted by the document in an xattr)

    private var restoredState = false

    override func viewDidAppear() {
        super.viewDidAppear()
        // First appearance only: the view has its real width, so wrapping matches.
        guard !restoredState else { return }
        restoredState = true
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidEndLiveResize(_:)),
                                               name: NSWindow.didEndLiveResizeNotification, object: view.window)
        restoreOrPlaceAtEnd(document?.savedState)
    }

    var state: EditorState {
        let sel = textView.selectedRange()
        let atEnd = sel.length == 0 && sel.location == (textView.string as NSString).length
        return EditorState(sel: [sel.location, sel.length], scroll: topCharacterIndex(), end: atEnd ? true : nil)
    }

    /// No stored state: the caret goes to the end of the text, scrolled into view.
    private func restoreOrPlaceAtEnd(_ state: EditorState?) {
        if let state { restore(state); return }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Clamped to the current text: the file may have been edited elsewhere.
    func restore(_ state: EditorState) {
        let length = (textView.string as NSString).length
        if state.end == true {
            textView.setSelectedRange(NSRange(location: length, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            return
        }
        if state.sel.count == 2 {
            let location = min(max(state.sel[0], 0), length)
            textView.setSelectedRange(NSRange(location: location, length: min(max(state.sel[1], 0), length - location)))
        }
        scroll(toCharacter: min(max(state.scroll, 0), length))
    }

    /// Index of the first character on the topmost visible line.
    private func topCharacterIndex() -> Int {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage,
              let clip = textView.enclosingScrollView?.contentView else { return 0 }
        let y = max(clip.bounds.minY - textView.textContainerOrigin.y, 0)
        guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return 0 }
        var index = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let lineY = y - fragment.layoutFragmentFrame.minY
        if let line = fragment.textLineFragments.first(where: { $0.typographicBounds.maxY > lineY }) {
            index += line.characterRange.location
        }
        return index
    }

    /// Scrolls so the line holding character `index` is at the top.
    private func scroll(toCharacter index: Int) {
        guard index > 0, let layout = textView.textLayoutManager, let content = textView.textContentStorage,
              let scrollView = textView.enclosingScrollView,
              let target = content.location(content.documentRange.location, offsetBy: index),
              let upTo = NSTextRange(location: content.documentRange.location, end: target) else { return }
        // Real layout up to the target, not TextKit 2's height estimate.
        layout.ensureLayout(for: upTo)
        guard let fragment = layout.textLayoutFragment(for: target) else { return }
        let offset = content.offset(from: fragment.rangeInElement.location, to: target)
        let line = fragment.textLineFragments.last { $0.characterRange.location <= offset }
        let y = fragment.layoutFragmentFrame.minY + (line?.typographicBounds.minY ?? 0)
            + textView.textContainerOrigin.y
        textView.scroll(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: View settings: typewriter, focus, text size, spelling
    // Each window keeps its own; the last choice is remembered in UserDefaults and new
    // windows start from it. None of these change the text storage's characters or
    // register undo, so the document never becomes edited.

    enum DefaultsKey {
        static let typewriter = "TypewriterMode", focus = "FocusMode", focusScope = "FocusScope",
                   textSize = "TextSizeStep", pasteRichAsMarkdown = "PasteRichTextAsMarkdown", spelling = "ContinuousSpellChecking", grammar = "GrammarChecking"
    }
    private static let defaults: UserDefaults = {
        AppDefaults.store.register(defaults: [DefaultsKey.spelling: true, DefaultsKey.grammar: false])
        return AppDefaults.store
    }()

    private static let inset = NSSize(width: 24, height: 24)
    /// ⌘+ / ⌘− steps of 10% each, from about 60% to about 260%.
    static let textSizeSteps = -5...10

    private var typewriter = false
    private var focus = false
    private var focusScope = FocusRange.Scope.sentence
    private var textSizeStep = 0
    private var textScale: CGFloat { pow(1.1, CGFloat(textSizeStep)) }
    private var checkingObservers: [NSKeyValueObservation] = []

    private func loadViewSettings() {
        let d = Self.defaults
        typewriter = d.bool(forKey: DefaultsKey.typewriter)
        focus = d.bool(forKey: DefaultsKey.focus)
        focusScope = FocusRange.Scope(rawValue: d.integer(forKey: DefaultsKey.focusScope)) ?? .sentence
        textSizeStep = min(max(d.integer(forKey: DefaultsKey.textSize), Self.textSizeSteps.lowerBound),
                           Self.textSizeSteps.upperBound)
        textView.font = MarkdownStyler.baseFont(scale: textScale)
        textView.isContinuousSpellCheckingEnabled = d.bool(forKey: DefaultsKey.spelling)
        textView.isGrammarCheckingEnabled = d.bool(forKey: DefaultsKey.grammar)
        NotificationCenter.default.addObserver(self, selector: #selector(textViewFrameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: textView)
        // Edit ▸ Spelling and Grammar toggles these on the text view; remember the choice.
        checkingObservers = [
            textView.observe(\.isContinuousSpellCheckingEnabled) { tv, _ in
                MainActor.assumeIsolated { Self.defaults.set(tv.isContinuousSpellCheckingEnabled, forKey: DefaultsKey.spelling) }
            },
            textView.observe(\.isGrammarCheckingEnabled) { tv, _ in
                MainActor.assumeIsolated { Self.defaults.set(tv.isGrammarCheckingEnabled, forKey: DefaultsKey.grammar) }
            },
        ]
    }

    @objc func toggleTypewriterMode(_ sender: Any?) {
        typewriter.toggle()
        Self.defaults.set(typewriter, forKey: DefaultsKey.typewriter)
        updateTypewriter()
    }

    @objc func toggleFocusMode(_ sender: Any?) {
        focus.toggle()
        Self.defaults.set(focus, forKey: DefaultsKey.focus)
        updateFocus()
    }

    /// Menu items carry the scope's raw value as their tag.
    @objc func setFocusScope(_ sender: NSMenuItem) {
        focusScope = FocusRange.Scope(rawValue: sender.tag) ?? .sentence
        Self.defaults.set(focusScope.rawValue, forKey: DefaultsKey.focusScope)
        updateFocus()
    }

    @objc func makeTextBigger(_ sender: Any?) { setTextSizeStep(textSizeStep + 1) }
    @objc func makeTextSmaller(_ sender: Any?) { setTextSizeStep(textSizeStep - 1) }
    @objc func makeTextActualSize(_ sender: Any?) { setTextSizeStep(0) }

    private func setTextSizeStep(_ step: Int) {
        guard Self.textSizeSteps.contains(step), step != textSizeStep else { return }
        textSizeStep = step
        Self.defaults.set(step, forKey: DefaultsKey.textSize)
        // The visible text restyles now, the rest after a background parse
        // (attribute changes only: no undo, no edit).
        styler?.setScale(textScale, visible: visibleCharacterRange())
        textView.typingAttributes[.font] = MarkdownStyler.baseFont(scale: textScale)
        centerCaretSoon()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        centerCaretSoon()
        if focus { updateFocus() }
        updateCompletion(typed: false)
    }

    func textDidChange(_ notification: Notification) {
        centerCaretSoon()
        if focus { updateFocus() }  // e.g. forward delete: text changed, selection didn't
        // Typing (not undo/redo, not accepting a completion) may open the list. Checked
        // once the change has settled: a command's edit sets its selection afterwards.
        let undo = textView.undoManager
        let typed = !acceptingCompletion && undo?.isUndoing != true && undo?.isRedoing != true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.updateCompletion(typed: typed) }
        }
    }

    /// TextKit 2 re-estimates heights as it lays out and resizes the text view, which can
    /// move the caret's line without a scroll (after a restyle, most of all); follow it,
    /// unless the user has scrolled away since the last centring.
    @objc private func textViewFrameDidChange(_ notification: Notification) {
        guard textView.enclosingScrollView?.contentView.bounds.minY == centeredAt else { return }
        centerCaretSoon()
    }
    /// The clip view's origin right after the last centring.
    private var centeredAt: CGFloat?

    /// Centres once an edit, selection change, restyle or re-estimate has settled (a
    /// typed Return moves the selection before TextKit 2 has laid out the new last
    /// line), however many of them asked during this turn. The main queue runs
    /// before this run-loop turn's display pass, so nothing flickers.
    private func centerCaretSoon() {
        guard typewriter, !centringScheduled else { return }
        centringScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.centringScheduled = false
                self?.centerCaret()
            }
        }
    }
    private var centringScheduled = false
    /// Whether a mouse button is down; internal so the headless harness can stand in for it.
    var isMouseDown: () -> Bool = { NSEvent.pressedMouseButtons != 0 }

    /// The visible height the typewriter insets were last set for.
    private var typewriterHeight: CGFloat?
    private var appliedFocusOnLayout = false

    override func viewDidLayout() {
        super.viewDidLayout()
        // A remembered focus mode applies once the view is laid out.
        if focus, !appliedFocusOnLayout { appliedFocusOnLayout = true; updateFocus() }
        // The half-height insets follow the visible height: only when it changed, and
        // not on every step of a live resize (its end catches up).
        guard typewriter, !view.inLiveResize,
              textView.enclosingScrollView?.contentView.bounds.height != typewriterHeight else { return }
        updateTypewriter()
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        if typewriter { updateTypewriter() }
    }

    /// On: insets of half the visible height above and below the text, so the first and
    /// last lines can reach the middle, and the caret's line centred. Off: normal insets.
    private func updateTypewriter() {
        guard let clip = textView.enclosingScrollView?.contentView else { return }
        typewriterHeight = typewriter ? clip.bounds.height : nil
        let inset = typewriter ? NSSize(width: Self.inset.width, height: (clip.bounds.height / 2).rounded()) : Self.inset
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        centerCaretSoon()
    }

    /// Scrolls so the middle of the caret's line is at the middle of the visible area.
    /// Only a caret (a selection is left where the user put it, ⌘A included), and not
    /// while the mouse is down (a click or a drag-selection and its autoscroll).
    private func centerCaret() {
        guard typewriter, textView.selectedRange().length == 0, !isMouseDown(),
              let rect = caretLineRect(), let scrollView = textView.enclosingScrollView else { return }
        let clip = scrollView.contentView
        var bounds = clip.bounds
        bounds.origin.y = rect.midY - bounds.height / 2
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scrollView.reflectScrolledClipView(clip)
        centeredAt = clip.bounds.minY
    }

    /// The caret's line, in text view coordinates, from its TextKit 2 line fragment.
    private func caretLineRect() -> CGRect? {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage else { return nil }
        let start = content.documentRange.location
        let index = textView.selectedRange().location
        guard let caret = content.location(start, offsetBy: index) else { return nil }
        // Real layout for the caret's paragraph only; above it TextKit 2's estimates
        // stand, as they do when the user scrolls there.
        // At the very end there is no fragment *at* the caret; use the last one.
        let before = index > 0 ? content.location(start, offsetBy: index - 1) : nil
        guard let fragment = layout.textLayoutFragment(for: caret) ?? before.flatMap({ layout.textLayoutFragment(for: $0) })
        else { return nil }
        layout.ensureLayout(for: fragment.rangeInElement)
        let offset = content.offset(from: fragment.rangeInElement.location, to: caret)
        let line = fragment.textLineFragments.last { $0.characterRange.location <= offset }
        let frame = fragment.layoutFragmentFrame
        let bounds = line?.typographicBounds ?? CGRect(origin: .zero, size: frame.size)
        return bounds.offsetBy(dx: frame.minX + textView.textContainerOrigin.x,
                               dy: frame.minY + textView.textContainerOrigin.y)
    }

    /// The document replaced the whole text (open, revert): the text view sends no
    /// change notification for that, so refresh what follows the text and caret,
    /// once the text view has settled its selection.
    func textReloaded() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.focus { self.updateFocus() }
                self.centerCaretSoon()
            }
        }
    }

    /// The characters TextKit 2 has laid out for display (the viewport), or the caret.
    private func visibleCharacterRange() -> NSRange {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage,
              let viewport = layout.textViewportLayoutController.viewportRange
        else { return NSRange(location: textView.selectedRange().location, length: 0) }
        let a = content.offset(from: content.documentRange.location, to: viewport.location)
        return NSRange(location: a, length: content.offset(from: viewport.location, to: viewport.endLocation))
    }

    /// Dims everything outside the caret's sentence or paragraph with TextKit 2
    /// rendering attributes: drawn over the text but never stored in the text storage,
    /// so the styler, the document and storage observers never see them.
    private func updateFocus() {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage else { return }
        layout.removeRenderingAttribute(.foregroundColor, for: content.documentRange)
        guard focus else { return }
        let text = textView.string
        let length = (text as NSString).length
        let kept = FocusRange.range(in: text, selection: textView.selectedRange(), scope: focusScope)
        let start = content.documentRange.location
        for r in [NSRange(location: 0, length: kept.location),
                  NSRange(location: NSMaxRange(kept), length: length - NSMaxRange(kept))] where r.length > 0 {
            guard let a = content.location(start, offsetBy: r.location),
                  let b = content.location(a, offsetBy: r.length),
                  let range = NSTextRange(location: a, end: b) else { continue }
            layout.setRenderingAttributes([.foregroundColor: NSColor.tertiaryLabelColor], for: range)
        }
    }
}

/// The editor's text view: Paste first offers the pasteboard to `richPaste` (the "Paste Rich
/// Text as Markdown" setting), then pastes as usual.
final class EditorTextView: NSTextView {
    var richPaste: (() -> Bool)?
    override func paste(_ sender: Any?) {
        if richPaste?() == true { return }
        super.paste(sender)
    }
    /// Paste as the stock text view does, without offering the pasteboard to `richPaste` again.
    func pasteWithoutRichText(_ sender: Any?) { super.paste(sender) }

    /// The context menu gains the Copy as items, after Copy.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        let at = (menu.items.firstIndex { $0.action == #selector(NSText.copy(_:)) } ?? menu.items.count - 1) + 1
        let entries: [(String, Selector)] = [
            ("Copy as Markdown", #selector(EditorViewController.copyAsMarkdown(_:))),
            ("Copy as HTML", #selector(EditorViewController.copyAsHTML(_:))),
            ("Copy as Rich Text", #selector(EditorViewController.copyAsRichText(_:))),
            ("Copy as Plain Text", #selector(EditorViewController.copyAsPlainText(_:))),
        ]
        for (i, entry) in entries.enumerated() where !menu.items.contains(where: { $0.action == entry.1 }) {
            menu.insertItem(NSMenuItem(title: entry.0, action: entry.1, keyEquivalent: ""), at: min(at + i, menu.items.count))
        }
        return menu
    }
}
