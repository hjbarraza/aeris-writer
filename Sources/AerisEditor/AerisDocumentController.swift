import AppKit

/// File > Open… also takes folders: a chosen folder becomes a library location (like Add Location…),
/// chosen files open as documents.
final class AerisDocumentController: NSDocumentController {
    /// The self-check never adds its temp files to the user's Open Recent.
    override func noteNewRecentDocumentURL(_ url: URL) {
        if AppDefaults.isolated { return }
        super.noteNewRecentDocumentURL(url)
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.canChooseDirectories = true
        return super.runModalOpenPanel(openPanel, forTypes: types)
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
