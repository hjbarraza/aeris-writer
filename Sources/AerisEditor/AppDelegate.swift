import AppKit

/// App delegate. Document windows come from NSDocumentController via the Info.plist
/// document types (an untitled document at launch, or the file Finder opened);
/// this only installs the main menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Before anything touches Library.shared: the self-check never uses H's real library file.
        if CommandLine.arguments.contains("--selfcheck") { SelfCheck.isolateLibraryFile() }
        #endif
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--selfcheck") { SelfCheck.run() }
        #endif
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        #if DEBUG
        return !CommandLine.arguments.contains("--selfcheck")
        #else
        return true
        #endif
    }

    /// File > Add Location…: pick folders to list in the library sidebar.
    @MainActor @objc func addLocation(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { Library.shared.addLocation($0) }
        if let wc = NSApp.keyWindow?.windowController as? EditorWindowController, wc.isSidebarCollapsed {
            wc.splitViewController.showLibrary()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
