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
    /// Waiting for the folder save under way (a close or autosave that came during it).
    private var settleWaiters: [(Bool) -> Void] = []
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
    /// `done(true)` once it has its file; `done(false)` if it is blank or failed (a failure is
    /// shown, and the draft becomes a normal untitled document). While a save is under way, `done`
    /// waits for its outcome.
    private func settle(_ done: @escaping (Bool) -> Void = { _ in }) {
        if settling { return settleWaiters.append(done) }
        guard awaitsFile, !isBlank, let folder else { return done(false) }
        settling = true
        let fm = FileManager.default
        let url: URL
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // The name is claimed by creating it exclusively (anything there, a broken symlink
            // included, counts as taken), so no other draft or app can get it before the save
            // replaces this empty placeholder.
            var claimError: Int32 = 0
            let name = DraftName.unique(DraftName.make(textStorage.string), ext: DraftSettings.fileExtension) {
                let fd = open(folder.appending(path: $0).path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
                if fd >= 0 { Darwin.close(fd); return false }
                if errno == EEXIST { return true }
                claimError = errno
                return false
            }
            if claimError != 0 { throw POSIXError(POSIXErrorCode(rawValue: claimError) ?? .EIO) }
            url = folder.appending(path: name)
        } catch {
            return failed(error, done)
        }
        // The type the file's extension gives (plain text for a .txt draft).
        let type = (try? NSDocumentController.shared.typeForContents(of: url)) ?? fileType ?? "net.daringfireball.markdown"
        save(to: url, ofType: type, for: .saveAsOperation) { error in
            if let error {
                // The name was claimed for this draft: the placeholder, or a partly written file, goes.
                try? fm.removeItem(at: url)
                return self.failed(error, done)
            }
            self.finish(true, done)
        }
    }

    private func failed(_ error: Error, _ done: (Bool) -> Void) {
        folder = nil
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        Self.presentSaveFailure(self, error)
        finish(false, done)
    }

    private func finish(_ saved: Bool, _ done: (Bool) -> Void) {
        settling = false
        done(saved)
        let waiters = settleWaiters
        settleWaiters = []
        waiters.forEach { $0(saved) }
    }

    /// A draft is written with no save panel: Finder shows its extension.
    override var fileNameExtensionWasHiddenInLastRunSavePanel: Bool {
        settling ? false : super.fileNameExtensionWasHiddenInLastRunSavePanel
    }

    /// A draft's autosave is its first save into the folder (or waits for the one under way); a
    /// blank draft writes nothing, and a failed one falls back to the usual untitled autosave.
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

    /// Closing a draft saves it into the folder (waiting for a save already under way), or, when
    /// blank, closes it without a prompt.
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
