import AppKit
import MarkdownCore
import UniformTypeIdentifiers

/// Preferences for File ▸ New (M2-8), until the Preferences window (M4-0) shows them.
enum DraftSettings {
    /// "untitled" makes ⌘N the classic untitled document; anything else makes it a draft.
    static let newDocumentKey = "Aeris.NewDocument"
    /// The extension of a draft's file: a plain-text one, else `md`.
    static let extensionKey = "Aeris.DraftExtension"

    static var newMakesDraft: Bool { AppDefaults.store.string(forKey: newDocumentKey) != "untitled" }

    static var fileExtension: String {
        let ext = (AppDefaults.store.string(forKey: extensionKey) ?? "")
            .trimmingCharacters(in: .whitespaces).drop { $0 == "." }.lowercased()
        guard !ext.isEmpty, !ext.contains("/"), UTType(filenameExtension: ext)?.conforms(to: .plainText) == true
        else { return "md" }
        return ext
    }
}

/// File ▸ New with a library folder shown (M2-8): an untitled document that belongs to `folder`.
/// While untitled its title is its cleaned first line. Return after a non-empty first line, the
/// first autosave, or closing it writes it into the folder with no dialog, named by `DraftName`
/// (never over an existing file). From then on it is an ordinary document: the name never changes.
/// An empty draft is never written and closes without a prompt.
final class DraftDocument: MarkdownDocument {
    /// The folder the draft saves into; nil once a save into it failed (it is then a normal
    /// untitled document, so nothing typed can be lost).
    private(set) var folder: URL?
    private var settling = false
    private var shownName = "Untitled"

    /// Shows why the draft couldn't be written. A seam so the self-check shows no sheet.
    @MainActor static var presentSaveFailure: (DraftDocument, Error) -> Void = { doc, error in
        if let window = doc.windowForSheet {
            doc.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            doc.presentError(error)
        }
    }

    init(folder: URL) {
        self.folder = folder
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    /// Still a draft: no file yet and a folder to go to.
    private var awaitsFile: Bool { folder != nil && fileURL == nil }
    private var isBlank: Bool { textStorage.string.allSatisfy(\.isWhitespace) }

    override var displayName: String! {
        get { awaitsFile ? DraftName.make(textStorage.string) : super.displayName }
        set { super.displayName = newValue }
    }

    @objc private func textDidChange(_ note: Notification) {
        guard awaitsFile, textStorage.editedMask.contains(.editedCharacters) else { return }
        let name = DraftName.make(textStorage.string)
        if name != shownName {
            shownName = name
            windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        }
        // Return after a non-empty first line settles the name.
        let edited = textStorage.editedRange
        guard edited.length > 0, NSMaxRange(edited) <= textStorage.length,
              (textStorage.string as NSString).substring(with: edited).contains(where: \.isNewline),
              !textStorage.string.prefix(while: { !$0.isNewline }).allSatisfy(\.isWhitespace)
        else { return }
        // Not from inside text storage processing.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.settle() } }
    }

    /// Writes the draft into its folder (created if missing) under its first line's name.
    /// `done(true)` once it has its file; `done(false)` if it is blank, already settling or failed
    /// (a failure is shown, and the draft becomes a normal untitled document).
    private func settle(_ done: @escaping (Bool) -> Void = { _ in }) {
        guard awaitsFile, !isBlank, !settling, let folder else { return done(false) }
        settling = true
        let fm = FileManager.default
        let url: URL
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = DraftName.unique(DraftName.make(textStorage.string), ext: DraftSettings.fileExtension) {
                fm.fileExists(atPath: folder.appending(path: $0).path)
            }
            url = folder.appending(path: name)
        } catch {
            return failed(error, done)
        }
        save(to: url, ofType: fileType ?? "net.daringfireball.markdown", for: .saveAsOperation) { error in
            if let error { return self.failed(error, done) }
            self.settling = false
            done(true)
        }
    }

    private func failed(_ error: Error, _ done: (Bool) -> Void) {
        settling = false
        folder = nil
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        Self.presentSaveFailure(self, error)
        done(false)
    }

    /// A draft's autosave is its first save into the folder; a blank draft writes nothing, and a
    /// failed one falls back to the usual untitled autosave.
    override func autosave(withImplicitCancellability autosavingIsImplicitlyCancellable: Bool,
                           completionHandler: @escaping (Error?) -> Void) {
        guard awaitsFile else {
            return super.autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable,
                                  completionHandler: completionHandler)
        }
        if isBlank { return completionHandler(nil) }
        settle { saved in
            if saved { return completionHandler(nil) }
            super.autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable,
                           completionHandler: completionHandler)
        }
    }

    /// Closing a draft saves it into the folder, or, when blank, closes it without a prompt.
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        guard awaitsFile else {
            return super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        if isBlank {
            updateChangeCount(.changeCleared)
            return super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        nonisolated(unsafe) let delegate = delegate
        settle { _ in
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
    }
}
