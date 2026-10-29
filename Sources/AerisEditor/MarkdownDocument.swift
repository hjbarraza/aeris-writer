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

    /// The encoding of the write in progress: the file's own for saves to its file,
    /// UTF-8 for a new file (Save As, Save To, a duplicate's first save).
    private var writeEncoding: TextEncoding?
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

    /// From now on the document saves as UTF-8 without a BOM.
    func convertToUTF8() {
        encoding = .utf8
        keepsUnstorableEncoding = false
    }

    /// Set by the "Save as UTF-8" error recovery, after which NSDocument closes without
    /// retrying the failed save; `canClose` saves first instead.
    fileprivate var saveBeforeClosing = false
    private var closeAnswer: CloseAnswer?

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        nonisolated(unsafe) let delegate = delegate, contextInfo = contextInfo
        func forward(_ ok: Bool) {
            guard let target = delegate as? NSObject, let selector = shouldCloseSelector else { return }
            typealias ShouldClose = @convention(c) (NSObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(target.method(for: selector), to: ShouldClose.self)(target, selector, self, ok, contextInfo)
        }
        let answer = CloseAnswer { [self] ok in
            closeAnswer = nil
            guard ok, saveBeforeClosing, let url = fileURL, let type = fileType else { return forward(ok) }
            saveBeforeClosing = false
            // An explicit write: after the recovery NSDocument counts the change as saved,
            // so a plain autosave would find nothing to do.
            save(to: url, ofType: type, for: .autosaveInPlaceOperation) { forward($0 == nil) }
        }
        closeAnswer = answer  // NSDocument doesn't retain the delegate.
        super.canClose(withDelegate: answer, shouldClose: #selector(CloseAnswer.document(_:shouldClose:contextInfo:)),
                       contextInfo: nil)
    }

    override class var autosavesInPlace: Bool { true }

    // Reads must run on the main thread; read(from:ofType:) relies on it.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController())
    }

    override func data(ofType typeName: String) throws -> Data {
        let target = writeEncoding ?? encoding
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
        // A new file is always UTF-8; only a save to the document's own file keeps its encoding.
        let newFile = saveOperation == .saveAsOperation || url.standardizedFileURL != fileURL?.standardizedFileURL
        writeEncoding = newFile ? .utf8 : encoding
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            self.writeEncoding = nil
            // After Save As the document is the new UTF-8 file.
            if error == nil, saveOperation == .saveAsOperation { self.convertToUTF8() }
            // Only saves to the document's own file (not Export, not autosave-elsewhere).
            if error == nil, url.standardizedFileURL == self.fileURL?.standardizedFileURL {
                self.writeEditorState()
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

/// The "Save as UTF-8" option of an encoding save error: converts the document. NSDocument
/// calls only the synchronous variant and does not retry the failed save, so the document
/// is marked to save before it closes (see `MarkdownDocument.canClose`).
private final class SaveAsUTF8Recovery: NSObject {
    weak var document: MarkdownDocument?

    init(document: MarkdownDocument) { self.document = document }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int) -> Bool {
        guard recoveryOptionIndex == 0, let document else { return false }
        MainActor.assumeIsolated {
            document.convertToUTF8()
            document.saveBeforeClosing = true
        }
        return true
    }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int, delegate: Any?,
                                  didRecoverSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let recovered = attemptRecovery(fromError: error, optionIndex: recoveryOptionIndex)
        guard let target = delegate as? NSObject, let selector = didRecoverSelector else { return }
        typealias DidRecover = @convention(c) (NSObject, Selector, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(target.method(for: selector), to: DidRecover.self)(target, selector, recovered, contextInfo)
    }
}

/// Receives NSDocument's close answer so `MarkdownDocument.canClose` can act on it first.
private final class CloseAnswer: NSObject {
    let handle: (Bool) -> Void
    init(_ handle: @escaping (Bool) -> Void) { self.handle = handle }
    @objc func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        handle(shouldClose)
    }
}
