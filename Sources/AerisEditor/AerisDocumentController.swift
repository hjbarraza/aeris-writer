import AppKit
import UniformTypeIdentifiers

/// File > Open… also takes folders: a chosen folder becomes a library location (like Add Location…),
/// chosen files open as documents.
final class AerisDocumentController: NSDocumentController {
    /// The self-check never adds its temp files to the user's Open Recent.
    override func noteNewRecentDocumentURL(_ url: URL) {
        if AppDefaults.isolated { return }
        super.noteNewRecentDocumentURL(url)
    }

    /// File ▸ New (⌘N): with a library folder shown, a draft that saves itself into that folder
    /// (M2-8); otherwise, or when the setting says so, the classic untitled document.
    @MainActor @objc func newDraft(_ sender: Any?) {
        let source = (NSApp.mainWindow ?? NSApp.keyWindow)?.windowController as? EditorWindowController
        guard let draft = makeDraft(from: source) else { return newDocument(sender) }
        draft.showWindows()
    }

    /// A draft for the folder `source` lists, in a window showing that folder; nil when ⌘N is set
    /// to the classic untitled document or `source` lists no folder.
    @MainActor func makeDraft(from source: EditorWindowController?) -> DraftDocument? {
        guard DraftSettings.newMakesDraft, let source, let folder = source.fileList.folder?.url else { return nil }
        let draft = DraftDocument(folder: folder)
        draft.fileType = defaultType
        addDocument(draft)
        draft.makeWindowControllers()
        (draft.windowControllers.first as? EditorWindowController)?.restoreLibraryView(
            folderPath: folder.path, selectedPath: nil, expandedPaths: source.sidebar.expandedFolderPaths)
        return draft
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.canChooseDirectories = true
        // Any file can be chosen: one whose bytes are text opens (MarkdownDocument refuses the rest).
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }

    /// A file of a type no document class reads (`README`, an empty file, `notes.log`) is read
    /// as plain text; MarkdownDocument refuses it unless its bytes decode cleanly as text.
    override func typeForContents(of url: URL) throws -> String {
        let type = try super.typeForContents(of: url)
        return documentClass(forType: type) == nil ? UTType.plainText.identifier : type
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        // Only a real folder becomes a location; a package (.rtfd, .app) is opened as a file and refused.
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isPackage != true else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        MainActor.assumeIsolated {
            if let wc = NSApp.keyWindow?.windowController as? EditorWindowController {
                wc.sidebar.addLocations([url])
                if wc.isSidebarCollapsed { wc.splitViewController.showLibrary() }
            } else {
                Library.shared.addLocation(url)
            }
        }
        completionHandler(nil, false, nil)
    }
}
