import AppKit

/// Every app preference goes through `store`: the user's defaults normally, a private domain
/// under `--selfcheck`, so a self-check never changes the user's settings. (AppKit's own split
/// view autosave always writes the standard defaults; the self-check uses its own names there.)
enum AppDefaults {
    static let selfCheckSuite = "com.aeris.editor.selfcheck"
    nonisolated(unsafe) static var store: UserDefaults = .standard
    /// True under `--selfcheck`: windows are not restorable.
    nonisolated(unsafe) static var isolated = false
}

/// App delegate. Document windows come from NSDocumentController via the Info.plist
/// document types (an untitled document at launch, or the file Finder opened);
/// this only installs the main menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True until launch is done: only a launch reopens the last session, not a Dock click.
    private var launching = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Before anything touches Library.shared: the self-check never uses H's real library file.
        if CommandLine.arguments.contains("--selfcheck") { SelfCheck.isolateLibraryFile(); SelfCheck.isolateDefaults() }
        #endif
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cleared after this turn, in case AppKit asks about an untitled file right after this.
        DispatchQueue.main.async { self.launching = false }
        #if DEBUG
        if CommandLine.arguments.contains("--selfcheck") { SelfCheck.run() }
        #endif
    }

    /// Called when no window was restored and no file was opened: at launch the last session
    /// reopens (M2-6a); with none stored, or later (a Dock click), an untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--selfcheck") { return false }
        #endif
        guard launching else { return true }
        launching = false
        return !EditorWindowController.reopenLastSession(display: true)
    }

    /// File > Add Location…: pick folders to list in the organizer.
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

    /// View > Organizer > (section): hides or shows Favorites, Smart Folders or Tags in every window.
    @MainActor @objc func toggleOrganizerSection(_ sender: NSMenuItem) {
        guard let kind = OrganizerSection.Kind(rawValue: sender.representedObject as? String ?? "") else { return }
        OrganizerSettings.setHidden(kind, !OrganizerSettings.isHidden(kind))
    }

    @MainActor @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleOrganizerSection(_:)),
           let kind = OrganizerSection.Kind(rawValue: item.representedObject as? String ?? "") {
            item.state = OrganizerSettings.isHidden(kind) ? .off : .on
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
