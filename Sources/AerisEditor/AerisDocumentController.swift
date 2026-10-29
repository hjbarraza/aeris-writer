import AppKit
import UniformTypeIdentifiers

/// File > Open… also takes folders: a chosen folder becomes a library location (like Add Location…),
/// chosen files open as documents.
final class AerisDocumentController: NSDocumentController {
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
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
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
