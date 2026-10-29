import AppKit
import LibraryCore

/// The file list's options, shared by every window and saved as they change.
@MainActor
final class FileListSettings {
    static let shared = FileListSettings(defaults: .standard)
    static let didChange = Notification.Name("AerisFileListOptionsDidChange")

    private let defaults: UserDefaults
    private(set) var options: FileListOptions

    init(defaults: UserDefaults) {
        self.defaults = defaults
        options = FileListOptions.load(from: defaults)
    }

    func update(_ change: (inout FileListOptions) -> Void) {
        var new = options
        change(&new)
        guard new != options else { return }
        options = new
        new.save(to: defaults)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// The sort and view-option items. The same items are offered by the sort bar, View ▸ Sort By and
/// View Options, and the list's context menu; every item acts on `FileListSettings.shared`.
@MainActor
final class FileListMenu: NSObject, NSMenuItemValidation {
    static let shared = FileListMenu()

    enum Command {
        case sortKey(SortKey), reversed(Bool), foldersOnTop, showDate(DateShown), showExcerpts, navigation(ListNavigation), sortBar
    }

    /// Fresh items each call (an item lives in one menu only): Sort By, View Options, Hide Sort Bar.
    func makeItems() -> [NSMenuItem] {
        let sortBy = submenu("Sort By", [
            item("Date Modified", .sortKey(.dateModified)),
            item("Date Created", .sortKey(.dateCreated)),
            item("Name", .sortKey(.name)),
            item("Extension", .sortKey(.fileExtension)),
            .separator(),
            item("Newest First", .reversed(false)),
            item("Oldest First", .reversed(true)),
            .separator(),
            item("Folders on Top", .foldersOnTop),
        ])
        let showDate = submenu("Show Date", [
            item("Modified", .showDate(.modified)),
            item("Created", .showDate(.created)),
            item("None", .showDate(.none)),
        ])
        let viewOptions = submenu("View Options", [
            showDate,
            item("Show Excerpts", .showExcerpts),
            .separator(),
            item("Navigation: Tree", .navigation(.tree)),
            item("Navigation: List", .navigation(.list)),
        ])
        return [sortBy, viewOptions, item("Hide Sort Bar", .sortBar)]
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        makeItems().forEach(menu.addItem)
        return menu
    }

    private func item(_ title: String, _ command: Command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = command
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? Command else { return }
        FileListSettings.shared.update { o in
            switch command {
            case .sortKey(let k): o.sortKey = k
            case .reversed(let r): o.reversed = r
            case .foldersOnTop: o.foldersOnTop.toggle()
            case .showDate(let d): o.showDate = d
            case .showExcerpts: o.showExcerpts.toggle()
            case .navigation(let n): o.navigation = n
            case .sortBar: o.showSortBar.toggle()
            }
        }
    }

    /// Checkmarks follow the options; the direction items read as dates or letters depending on the key.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let command = item.representedObject as? Command else { return true }
        let o = FileListSettings.shared.options
        switch command {
        case .sortKey(let k): item.state = o.sortKey == k ? .on : .off
        case .reversed(let r):
            item.state = o.reversed == r ? .on : .off
            item.title = FileListOptions.directionTitle(key: o.sortKey, reversed: r)
        case .foldersOnTop: item.state = o.foldersOnTop ? .on : .off
        case .showDate(let d): item.state = o.showDate == d ? .on : .off
        case .showExcerpts: item.state = o.showExcerpts ? .on : .off
        case .navigation(let n): item.state = o.navigation == n ? .on : .off
        case .sortBar: item.title = o.showSortBar ? "Hide Sort Bar" : "Show Sort Bar"
        }
        return true
    }
}
