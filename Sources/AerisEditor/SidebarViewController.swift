import AppKit
import LibraryCore

/// A section header row of the organizer.
@MainActor
final class OrganizerSection: NSObject {
    enum Kind: String, CaseIterable { case locations, favorites, smartFolders, tags }

    let kind: Kind
    let title: String
    /// The one-line row shown while the section has nothing in it (nil for Locations, which has the empty label).
    let hint: OrganizerHint?

    private init(_ kind: Kind, _ title: String, hint: String?) {
        self.kind = kind
        self.title = title
        self.hint = hint.map(OrganizerHint.init)
    }

    static let all: [OrganizerSection] = [
        OrganizerSection(.locations, "Locations", hint: nil),
        OrganizerSection(.favorites, "Favorites", hint: "Drop files or folders here"),
        OrganizerSection(.smartFolders, "Smart Folders", hint: "Save a search to find it again here"),
        OrganizerSection(.tags, "Tags", hint: "Type #tag in any file"),
    ]
}

/// The row that explains an empty organizer section.
@MainActor
final class OrganizerHint: NSObject {
    let text: String
    init(_ text: String) { self.text = text }
}

/// Which optional organizer sections are shown. Locations is always shown. Stored per layout key
/// like the rest of the window layout; the preferences pane will edit the same setting.
@MainActor
enum OrganizerSettings {
    static let didChange = Notification.Name("AerisOrganizerSettingsDidChange")

    private static var key: String { "\(EditorWindowController.layoutKey).HiddenSections" }

    static func isHidden(_ kind: OrganizerSection.Kind) -> Bool {
        kind != .locations && (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(kind.rawValue)
    }

    static func setHidden(_ kind: OrganizerSection.Kind, _ hidden: Bool) {
        guard kind != .locations, isHidden(kind) != hidden else { return }
        var kinds = UserDefaults.standard.stringArray(forKey: key) ?? []
        kinds.removeAll { $0 == kind.rawValue }
        if hidden { kinds.append(kind.rawValue) }
        UserDefaults.standard.set(kinds, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// The organizer: a source-list outline with the sections Locations, Favorites, Smart Folders and
/// Tags, and a "+" bar at the bottom. A location row fills the file list; folders below it are
/// walked in the list, not here.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let outlineView = NSOutlineView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "Add a folder to see its Markdown files here.")
    /// Set by the window controller: the user selected a location, whose folder the list should show.
    var onFolderSelected: (@MainActor (LibraryNode?) -> Void)?
    /// A programmatic reveal is selecting a row; that selection never fills the list.
    private var revealing = false
    /// The saved expansion is being applied; those expansions are not saved again.
    private var restoring = false

    /// Kinds of the sections the user collapsed, shared by every window and every launch.
    private var collapsedKey: String { "\(EditorWindowController.layoutKey).CollapsedSections" }
    private var collapsedSections: [String] {
        get { UserDefaults.standard.stringArray(forKey: collapsedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: collapsedKey) }
    }

    private var visibleSections: [OrganizerSection] { OrganizerSection.all.filter { !OrganizerSettings.isHidden($0.kind) } }

    /// The URL of the selected location (nil if nothing is selected).
    var selectedURL: URL? { (outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode)?.url }

    override func loadView() {
        outlineView.style = .sourceList
        outlineView.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(outlineClicked(_:))
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Location")!,
                           target: nil, action: #selector(AppDelegate.addLocation(_:)))
        add.isBordered = false
        add.toolTip = "Add Location…"

        let root = NSView()
        for sub in [scroll, emptyLabel, add] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -4),
            add.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            add.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            emptyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -8),
        ])
        view = root
        Library.shared.register(self)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)),
                                               name: OrganizerSettings.didChange, object: nil)
        libraryRootsDidChange()
    }

    /// The library's roots changed (a location was added, removed or re-resolved).
    func libraryRootsDidChange() {
        reloadKeepingSelection()
    }

    /// A View > Organizer item hid or showed a section.
    @objc private func settingsDidChange(_ notification: Notification) {
        reloadKeepingSelection()
    }

    private func reloadKeepingSelection() {
        let selected = outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode
        revealing = true
        defer { revealing = false }
        outlineView.reloadData()
        emptyLabel.isHidden = !Library.shared.tree.roots.isEmpty
        restoreExpansion()
        if let selected {
            let row = outlineView.row(forItem: selected)
            if row >= 0 { outlineView.selectRowIndexes([row], byExtendingSelection: false) }
        }
    }

    /// Expands every section the user has not collapsed (sections start expanded).
    private func restoreExpansion() {
        restoring = true
        defer { restoring = false }
        for section in visibleSections where !collapsedSections.contains(section.kind.rawValue) {
            outlineView.expandItem(section)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !restoring, let section = notification.userInfo?["NSObject"] as? OrganizerSection else { return }
        collapsedSections.removeAll { $0 == section.kind.rawValue }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !restoring, let section = notification.userInfo?["NSObject"] as? OrganizerSection,
              !collapsedSections.contains(section.kind.rawValue) else { return }
        collapsedSections.append(section.kind.rawValue)
    }

    /// Selects the location that holds `url`'s file and scrolls to it, expanding Locations if the
    /// user collapsed it. Deselects if `url` is nil or not in the library. Never fills the list.
    func reveal(_ url: URL?) {
        loadViewIfNeeded()
        revealing = true
        defer { revealing = false }
        guard let url, var node = Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url)) else {
            outlineView.deselectAll(nil)
            return
        }
        while let parent = node.parent { node = parent }
        // Opening Locations to show the row is not the user expanding it: their collapse stays saved.
        restoring = true
        outlineView.expandItem(OrganizerSection.all[0])
        restoring = false
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { outlineView.deselectAll(nil); return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: Context menu

    /// Right-click on a location row offers "Remove from Library"; other rows get no menu.
    func menuItems(forRow row: Int) -> [NSMenuItem] {
        guard row >= 0, let node = outlineView.item(atRow: row) as? LibraryNode,
              let index = Library.shared.tree.roots.firstIndex(where: { $0 === node }) else { return [] }
        let item = NSMenuItem(title: "Remove from Library", action: #selector(removeLocation(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        return [item]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = menuItems(forRow: outlineView.clickedRow)
    }

    @objc func removeLocation(_ sender: NSMenuItem) {
        Library.shared.removeLocation(at: sender.tag)
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return visibleSections.count }
        guard let section = item as? OrganizerSection else { return 0 }
        return section.kind == .locations ? Library.shared.tree.roots.count : 1
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let section = item as? OrganizerSection else { return visibleSections[index] }
        return section.kind == .locations ? Library.shared.tree.roots[index] : section.hint!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is OrganizerSection
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is OrganizerSection
    }

    /// Only a location can be selected; section titles and hints cannot.
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is LibraryNode
    }

    /// The user selected a location: its folder fills the file list.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !revealing, let node = outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode else { return }
        onFolderSelected?(node)
    }

    /// A click on a location row, even the selected one, brings the list back to the location's top.
    func locationClicked(row: Int) {
        guard let node = outlineView.item(atRow: row) as? LibraryNode else { return }
        onFolderSelected?(node)
    }

    @objc private func outlineClicked(_ sender: Any?) {
        locationClicked(row: outlineView.clickedRow)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let section as OrganizerSection:
            let cell = textCell("section")
            cell.textField?.stringValue = section.title
            cell.textField?.font = .systemFont(ofSize: 11, weight: .semibold)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        case let hint as OrganizerHint:
            let cell = textCell("hint")
            cell.textField?.stringValue = hint.text
            cell.textField?.font = .systemFont(ofSize: 11)
            cell.textField?.textColor = .tertiaryLabelColor
            return cell
        case let node as LibraryNode:
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
            let icon = NSWorkspace.shared.icon(forFile: node.path)
            icon.size = NSSize(width: 16, height: 16)
            cell.imageView?.image = icon
            let missing = !FileManager.default.fileExists(atPath: node.path)
            cell.textField?.stringValue = missing ? node.name + " (missing)" : node.name
            cell.textField?.textColor = missing ? .secondaryLabelColor : .labelColor
            return cell
        default:
            return nil
        }
    }

    private func textCell(_ identifier: String) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView { return cell }
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        for sub in [image, text] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(sub)
        }
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
