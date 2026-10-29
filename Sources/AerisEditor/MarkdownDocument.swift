import AppKit
import MarkdownCore

/// A plain-text Markdown document: the file's text is the whole model, kept in the
/// encoding it was read in (see `TextEncoding`).
/// Registered in Info.plist as NSDocumentClass `AerisEditor.MarkdownDocument`
/// for `net.daringfireball.markdown` and `public.plain-text`.
///
/// `textStorage` is the single source of truth: the editor's text view displays and
/// edits this storage directly, and save/revert read and replace it.
class MarkdownDocument: NSDocument {
    let textStorage = NSTextStorage()

    /// The editor showing this document; source of the caret/scroll state we persist.
    weak var editor: EditorViewController?
    /// Caret/scroll state read from the file's xattr on open, for the editor to restore.
    private(set) var savedState: EditorState?
    /// The file's encoding, detected on read; new documents are UTF-8 without a BOM.
    private(set) var encoding: TextEncoding = .utf8

    /// The user chose to keep the encoding although the text can't be stored in it;
    /// cleared once the text is storable again, so the next such edit asks again.
    private var keepsUnstorableEncoding = false
    private var askingAboutEncoding = false

    /// Asks whether to convert to UTF-8 after an edit the file's encoding can't store;
    /// `answer(true)` converts. A seam so the self-check can answer without a sheet.
    @MainActor static var askToConvert: (MarkdownDocument, _ example: String, _ answer: @escaping (Bool) -> Void) -> Void
        = { doc, example, answer in
            guard let window = doc.windowForSheet else { return answer(false) }
            let name = doc.encoding.displayName
            let alert = NSAlert()
            alert.messageText = "\(doc.displayName ?? "This document") is saved as \(name), "
                + "which can’t store some characters you typed (e.g. “\(example)”)."
            alert.informativeText = "Convert it to UTF-8 to save them. If you keep \(name), "
                + "the document can’t be saved until those characters are removed."
            alert.addButton(withTitle: "Convert to UTF-8")
            alert.addButton(withTitle: "Keep \(name)")
            alert.beginSheetModal(for: window) { answer($0 == .alertFirstButtonReturn) }
        }

    /// What another app or process did to the document's file.
    enum DiskChange { case modified, deleted, unreadable }

    /// Asks what to do about a change to the file on disk. `answer(true)` follows the disk
    /// (Reload, or Close for a deletion); `answer(false)` keeps the window's text (Ignore, or
    /// Keep). A seam so the self-check can answer without a sheet.
    @MainActor static var askAboutDiskChange: (MarkdownDocument, DiskChange, _ answer: @escaping (Bool) -> Void) -> Void
        = { doc, change, answer in
            // No window to ask in: the question stays open, so nothing is reloaded or closed.
            guard let window = doc.windowForSheet else { return }
            diskChangeAlert(for: doc, change).beginSheetModal(for: window) {
                answer($0 == (change == .modified ? .alertFirstButtonReturn : .alertSecondButtonReturn))
            }
        }

    /// The sheet that asks about `change`. The first button is Reload for a modification and
    /// keeps the window's text otherwise.
    static func diskChangeAlert(for doc: MarkdownDocument, _ change: DiskChange) -> NSAlert {
        let name = doc.displayName ?? "This document"
        let edited = doc.isDocumentEdited
        let alert = NSAlert()
        switch change {
        case .unreadable:
            alert.messageText = "“\(name)” was changed by another application, and its contents can’t be read as text."
            alert.informativeText = "Ignore keeps this version; saving it replaces the one on disk."
                + (edited ? " Closing discards your unsaved changes." : "")
            alert.addButton(withTitle: "Ignore")
            alert.addButton(withTitle: edited ? "Close Without Saving" : "Close").hasDestructiveAction = edited
        case .modified:
            alert.messageText = "“\(name)” was changed by another application."
            alert.informativeText = edited
                ? "Reload shows the version on disk, and your unsaved changes will be lost "
                    + "(Undo brings them back). Ignore keeps your version; saving it replaces the one on disk."
                : "Reload shows the version on disk. Ignore keeps this version; saving it replaces the one on disk."
            alert.addButton(withTitle: "Reload").hasDestructiveAction = edited
            alert.addButton(withTitle: "Ignore")
        case .deleted:
            alert.messageText = "“\(name)” was deleted by another application."
            alert.informativeText = (edited ? "It has unsaved changes. " : "")
                + "Keep it open to save it again in the same place, or close it."
                + (edited ? " Closing discards your unsaved changes." : "")
            alert.addButton(withTitle: "Keep")
            alert.addButton(withTitle: edited ? "Close Without Saving" : "Close").hasDestructiveAction = edited
        }
        return alert
    }

    /// Whether a file moved to `url` went to the Trash. A seam so the self-check never
    /// touches the real Trash.
    nonisolated(unsafe) static var isInTrash: (URL) -> Bool = { url in
        guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                       appropriateFor: url, create: false) else { return false }
        return url.resolvingSymlinksInPath().path.hasPrefix(trash.resolvingSymlinksInPath().path + "/")
    }

    /// The file's bytes as this document last read, wrote or accepted them. A change notice
    /// while the file still holds them (our own save, a caret xattr write) asks nothing.
    private var diskData: Data?
    private var askingAboutDisk = false
    /// The user chose Keep after the file was deleted: the next save may create it again.
    private var keepsDeletedFile = false
    /// Where the file was before it was moved to the Trash, for Keep to save it back there.
    private var trashedFrom: URL?

    // Called on NSDocument's file presenter queue.
    nonisolated override func presentedItemDidChange() {
        // Not super: it reloads a document without unsaved edits without asking.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.checkDisk() } }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        let old = presentedItemURL
        // Follows the file (the title updates). Moved to the Trash, it was deleted.
        super.presentedItemDidMove(to: newURL)
        guard Self.isInTrash(newURL) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // While another question is open, this one is asked once that is answered.
                self.trashedFrom = old
                if !self.askingAboutDisk { self.ask(.deleted) }
            }
        }
    }

    /// A coordinated delete (Finder, another app) asks at once; the document stays open.
    nonisolated override func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        // Not super: the question decides what happens to the document.
        completionHandler(nil)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !self.askingAboutDisk, !self.windowControllers.isEmpty { self.ask(.deleted) }
            }
        }
    }

    /// Another app deleting the file sends no change notice; coming back to Aeris checks.
    @objc private func appDidBecomeActive(_ note: Notification) { checkDisk() }

    private static func modificationDate(_ url: URL) -> Date? {
        // A fresh URL: a URL caches its resource values.
        try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Asks once if another app changed or deleted the file since this document last read,
    /// wrote or accepted it. Only with a window to ask in (a library switch reads its target first).
    private func checkDisk() {
        guard !askingAboutDisk, !windowControllers.isEmpty, let url = fileURL else { return }
        let date = Self.modificationDate(url)
        guard date == nil || date != fileModificationDate else { return }
        guard let data = try? Data(contentsOf: url) else {
            if !keepsDeletedFile, !FileManager.default.fileExists(atPath: url.path) { ask(.deleted) }
            return
        }
        if data == diskData { accept(data, of: url) } else { ask(.modified) }
    }

    /// From now on `data` counts as the file's contents, also for NSDocument's "changed by
    /// another application" check on save, which compares the modification date.
    private func accept(_ data: Data, of url: URL) {
        diskData = data
        fileModificationDate = Self.modificationDate(url)
    }

    private func ask(_ change: DiskChange) {
        askingAboutDisk = true
        Self.askAboutDiskChange(self, change) { followDisk in
            self.askingAboutDisk = false
            switch (change, followDisk) {
            case (.modified, true):
                self.reloadFromDisk()
            case (.modified, false), (.unreadable, false):
                // Ignore: whatever the file holds now (later writes included) is overwritten on save.
                if let url = self.fileURL, let data = try? Data(contentsOf: url) { self.accept(data, of: url) }
            case (.deleted, true), (.unreadable, true):
                self.trashedFrom = nil
                self.close()
                return
            case (.deleted, false):
                self.keepsDeletedFile = true
                if let original = self.trashedFrom { self.fileURL = original }
                self.trashedFrom = nil
                // Saved back now: NSDocument's ⌘S won't save to a file that no longer exists.
                self.updateChangeCount(.changeDone)
                self.autosave(withImplicitCancellability: false) { error in
                    guard let error, let window = self.windowForSheet else { return }
                    self.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                }
                return
            }
            // A move to the Trash during the question is asked now; otherwise the file may have
            // changed or gone since, which asks anew.
            guard !self.askingAboutDisk else { return }
            if self.trashedFrom != nil { self.ask(.deleted) } else { self.checkDisk() }
        }
    }

    /// Reload: the file's text replaces the window's as one undoable edit (text and encoding),
    /// in the encoding detected afresh. Not `read(from:)`, which clears the undo history.
    private func reloadFromDisk() {
        guard let url = fileURL, let editor, let data = try? Data(contentsOf: url) else { return }
        guard let (text, detected) = TextEncoding.decode(data) else {
            // Nothing is accepted, so autosave keeps off the file until the user picks Ignore.
            ask(.unreadable)
            return
        }
        let old = (encoding, keepsUnstorableEncoding)
        undoManager?.beginUndoGrouping()
        // Set before the text changes, so the new text is checked against its own encoding.
        encoding = detected
        keepsUnstorableEncoding = false
        let replaced = editor.replaceAllText(with: text, undoName: "Reload")
        // Registered after the text: undo restores the encoding first, then the old text.
        if replaced { registerEncodingUndo(old.0) }
        undoManager?.setActionName("Reload")
        undoManager?.endUndoGrouping()
        guard replaced else {
            (encoding, keepsUnstorableEncoding) = old
            return
        }
        accept(data, of: url)
        // Matches the disk. After NSDocument has counted the closed undo group as a change,
        // so the reload leaves it unedited and undoing the reload makes it edited again.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.updateChangeCount(.changeCleared) } }
    }

    private func registerEncodingUndo(_ previous: TextEncoding) {
        let current = encoding
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.encoding = previous
                doc.registerEncodingUndo(current)
            }
        }
    }

    /// While a disk change question is open the document stays: a close or a switch to
    /// another file could otherwise discard text the answer would keep.
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        guard askingAboutDisk else {
            return super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        guard let target = delegate as? NSObject, let selector = shouldCloseSelector else { return }
        typealias ShouldClose = @convention(c) (NSObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(target.method(for: selector), to: ShouldClose.self)(target, selector, self, false, contextInfo)
    }

    /// From now on the document saves as UTF-8 without a BOM.
    func convertToUTF8() {
        encoding = .utf8
        keepsUnstorableEncoding = false
    }

    override class var autosavesInPlace: Bool { true }

    // Reads must run on the main thread; read(from:ofType:) relies on it.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController())
    }

    override func data(ofType typeName: String) throws -> Data {
        try data(in: encoding)
    }

    /// Decided per write from its own operation, so overlapping saves can't mix encodings:
    /// a new file (Save As, Save To, a duplicate's first save) is UTF-8; every other write
    /// keeps the document's encoding.
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL: URL?) throws {
        let newFile = saveOperation == .saveAsOperation || saveOperation == .saveToOperation
        // Main thread: canAsynchronouslyWrite is not overridden (false).
        let data = try MainActor.assumeIsolated { try data(in: newFile ? .utf8 : encoding) }
        try data.write(to: url)
        // What the document's own file now holds, so this save's change notice asks nothing.
        if saveOperation != .saveToOperation, saveOperation != .autosaveElsewhereOperation {
            MainActor.assumeIsolated { diskData = data }
        }
    }

    private func data(in target: TextEncoding) throws -> Data {
        let text = textStorage.string
        guard let data = target.encode(text) else {
            // Never drop characters the file's encoding can't hold: fail the save instead,
            // offering UTF-8 when it can store the text.
            var info: [String: Any] = [
                NSLocalizedDescriptionKey: "\(displayName ?? "The document") can’t be saved as \(target.displayName).",
                NSLocalizedRecoverySuggestionErrorKey:
                    "\(target.displayName) can’t store some characters in the text. "
                    + "Save it as UTF-8, or remove those characters.",
            ]
            if target != .utf8, TextEncoding.utf8.encode(text) != nil {
                info[NSLocalizedRecoveryOptionsErrorKey] = ["Save as UTF-8", "Cancel"]
                info[NSRecoveryAttempterErrorKey] = SaveAsUTF8Recovery(document: self)
            }
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteInapplicableStringEncoding.rawValue,
                          userInfo: info)
        }
        return data
    }

    /// Asks once when an edit adds characters the file's encoding can't store.
    @objc private func checkEncodingAfterEdit(_ note: Notification) {
        guard textStorage.editedMask.contains(.editedCharacters) else { return }
        if keepsUnstorableEncoding {
            if encoding.encode(textStorage.string) != nil { keepsUnstorableEncoding = false }
            return
        }
        let edited = textStorage.editedRange
        guard !askingAboutEncoding, edited.length > 0, NSMaxRange(edited) <= textStorage.length else { return }
        let added = (textStorage.string as NSString).substring(with: edited)
        // Only when UTF-8 would help (it can't store an unpaired surrogate either).
        guard encoding.encode(added) == nil, TextEncoding.utf8.encode(added) != nil else { return }
        let example = added.first { encoding.encode(String($0)) == nil }.map(String.init) ?? added
        askingAboutEncoding = true
        // Not from inside text storage processing: the alert runs after this edit completes.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Self.askToConvert(self, example) { convert in
                    self.askingAboutEncoding = false
                    if convert { self.convertToUTF8() } else { self.keepsUnstorableEncoding = true }
                }
            }
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let (s, detected) = TextEncoding.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Safe only because canConcurrentlyReadDocuments returns false (main-thread reads).
        MainActor.assumeIsolated {
            // Saves write back in the encoding the file was read in.
            encoding = detected
            diskData = data
            // Plain text, no copied attributes: the editor's styler styles the new text.
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: NSRange(location: 0, length: textStorage.length),
                with: NSAttributedString(string: s)
            )
            textStorage.endEditing()
            // Old undo actions refer to text that no longer exists (e.g. after a revert).
            undoManager?.removeAllActions()
            // The text view sends no change notification for this; the editor refreshes.
            editor?.textReloaded()
        }
    }

    // MARK: Editor state in an extended attribute (never in the file's content)

    override func read(from url: URL, ofType typeName: String) throws {
        try super.read(from: url, ofType: typeName)
        let state = ExtendedAttributes.data(named: EditorState.attributeName, at: url)
            .flatMap { try? JSONDecoder().decode(EditorState.self, from: $0) }
        // Main thread: canConcurrentlyReadDocuments returns false.
        MainActor.assumeIsolated { savedState = state }
    }

    /// Safe-save writes a new file and swaps it in, which can drop xattrs set on the
    /// old one, so the state is written after the save completes, to the final file.
    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // An autosave never writes while a disk change question is open, nor over a file
        // changed or deleted elsewhere that this document hasn't noticed yet (it asks first),
        // so a deleted file is only re-created after Keep.
        if saveOperation == .autosaveInPlaceOperation, let own = fileURL,
           askingAboutDisk || Self.modificationDate(own).map({ $0 != fileModificationDate }) ?? !keepsDeletedFile {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.checkDisk() } }
            return completionHandler(CocoaError(.userCancelled))
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            // After Save As the document is the new UTF-8 file.
            if error == nil, saveOperation == .saveAsOperation { self.convertToUTF8() }
            // Only saves to the document's own file (not Export, not autosave-elsewhere).
            if error == nil, url.standardizedFileURL == self.fileURL?.standardizedFileURL {
                self.keepsDeletedFile = false
                self.writeEditorState()
                MainActor.assumeIsolated { Library.shared.refreshRows() }
            }
            completionHandler(error)
        }
    }

    /// Quit doesn't close unedited documents, so remember their caret on termination.
    /// (Edited ones are autosaved on quit, and that save writes the state.)
    private static let terminationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            for case let doc as MarkdownDocument in NSDocumentController.shared.documents
            where !doc.isDocumentEdited {
                doc.writeEditorState()
            }
        }
    }

    override init() {
        super.init()
        _ = Self.terminationObserver
        NotificationCenter.default.addObserver(
            self, selector: #selector(checkEncodingAfterEdit(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: textStorage)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    override func close() {
        // Closing without changes still remembers the caret. (A dirty document is
        // autosaved before closing, and that save writes the state.)
        if !isDocumentEdited { writeEditorState() }
        super.close()
    }

    /// The window is switching to another document: store this one's caret now, then
    /// let go of the editor, so this document never records the next document's caret.
    func detachEditor() {
        writeEditorState()
        editor = nil
    }

    /// Best effort: a failed xattr write is logged, never surfaced as a save failure.
    private func writeEditorState() {
        guard let url = fileURL, let state = editor?.state,
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try ExtendedAttributes.set(try encoder.encode(state), named: EditorState.attributeName, at: url)
        } catch {
            NSLog("Aeris: could not store editor state on \(url.path): \(error)")
        }
    }
}

/// The "Save as UTF-8" option of an encoding save error: converts the document, then
/// reports NOT recovered. NSDocument treats a recovery as a completed save without writing
/// anything; reporting failure keeps the document edited, so the next autosave or save
/// writes UTF-8 and a close or quit is simply asked again.
private final class SaveAsUTF8Recovery: NSObject {
    weak var document: MarkdownDocument?

    init(document: MarkdownDocument) { self.document = document }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int) -> Bool {
        guard recoveryOptionIndex == 0, let document else { return false }
        MainActor.assumeIsolated { document.convertToUTF8() }
        return false
    }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int, delegate: Any?,
                                  didRecoverSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let recovered = attemptRecovery(fromError: error, optionIndex: recoveryOptionIndex)
        guard let target = delegate as? NSObject, let selector = didRecoverSelector else { return }
        typealias DidRecover = @convention(c) (NSObject, Selector, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(target.method(for: selector), to: DidRecover.self)(target, selector, recovered, contextInfo)
    }
}
