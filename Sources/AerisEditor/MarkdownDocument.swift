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

    override class var autosavesInPlace: Bool { true }

    // Reads must run on the main thread; read(from:ofType:) relies on it.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController())
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = encoding.encode(textStorage.string) else {
            // Never drop characters the file's encoding can't hold: fail the save instead.
            throw CocoaError(.fileWriteInapplicableStringEncoding, userInfo: [
                NSLocalizedDescriptionKey: "The document couldn’t be saved in its text encoding.",
                NSLocalizedRecoverySuggestionErrorKey:
                    "This file uses the Western (Windows Latin 1) encoding, which can’t store some characters "
                    + "in the text, such as emoji. Remove those characters to save.",
            ])
        }
        return data
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
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
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
