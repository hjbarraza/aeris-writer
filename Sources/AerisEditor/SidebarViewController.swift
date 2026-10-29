import AppKit
import LibraryCore

/// The library sidebar: a source-list outline of the folders added to the library,
/// with a "+" bar at the bottom.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let outlineView = NSOutlineView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "Add a folder to see its Markdown files here.")
    /// Set by the window controller: opens a file row the user selected (mouse or arrow keys).
    var onOpen: (@MainActor (URL) -> Void)?
    /// A programmatic reveal is selecting a row; that selection never opens anything.
    private var revealing = false
    /// The saved expansion is being applied; those expansions are not saved again.
    private var restoring = false

    /// Canonical paths of the expanded folders, shared by every window and every launch.
    private var expandedPathsKey: String { "\(EditorWindowController.layoutKey).ExpandedPaths" }
    private var expandedPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: expandedPathsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: expandedPathsKey) }
    }

    var selectedURL: URL? { (outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode)?.url }

    override func loadView() {
        outlineView.style = .sourceList
        outlineView.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = self
        outlineView.delegate = self
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
        libraryRootsDidChange()
    }

    /// The library's roots changed (a location was added).
    func libraryRootsDidChange() {
        outlineView.reloadData()
        emptyLabel.isHidden = !Library.shared.tree.roots.isEmpty
        restoreExpansion()
    }

    /// Applies what a disk refresh changed. Only folders on screen are edited in place; a
    /// collapsed folder reloads when it is expanded. Unchanged folders keep their nodes, so
    /// they stay expanded. The selection is the user's: it is put back if the edit dropped it,
    /// never moved, and the view never scrolls.
    func apply(_ changes: [TreeChange]) {
        let selected = outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode
        revealing = true  // selection changes while rows are edited are never a request to open
        defer { revealing = false }
        outlineView.beginUpdates()
        for change in changes where outlineView.isItemExpanded(change.parent) {
            outlineView.removeItems(at: change.removed, inParent: change.parent, withAnimation: .effectFade)
            outlineView.insertItems(at: change.inserted, inParent: change.parent, withAnimation: .effectFade)
        }
        outlineView.endUpdates()
        // A renamed folder is a new node: expand it again if its new path is saved as expanded.
        if changes.contains(where: { change in change.inserted.contains { change.parent.children?[$0].isDirectory == true } }) {
            restoreExpansion()
        }
        if let selected, outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode !== selected {
            let row = outlineView.row(forItem: selected)
            if row >= 0 { outlineView.selectRowIndexes([row], byExtendingSelection: false) }
        }
    }

    /// Expands the folders saved as expanded (parents first) and drops saved paths that are
    /// gone, so a folder deleted since the last launch is forgotten. Paths under a root that is
    /// missing right now (an unmounted volume) are kept for when it returns.
    private func restoreExpansion() {
        restoring = true
        defer { restoring = false }
        let nodes = expandedPaths.sorted { $0.count < $1.count }.compactMap { path in
            Library.shared.tree.node(atPath: path).flatMap { $0.isDirectory ? $0 : nil }
        }
        nodes.forEach { outlineView.expandItem($0) }
        let expanded = Set(nodes.map(\.path))
        let roots = Library.shared.tree.roots
        expandedPaths = expandedPaths.filter { path in
            expanded.contains(path) || roots.contains {
                (path == $0.path || path.hasPrefix($0.path + "/")) && !FileManager.default.fileExists(atPath: $0.path)
            }
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !restoring, let node = notification.userInfo?["NSObject"] as? LibraryNode,
              !expandedPaths.contains(node.path) else { return }
        expandedPaths.append(node.path)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !restoring, let node = notification.userInfo?["NSObject"] as? LibraryNode else { return }
        expandedPaths.removeAll { $0 == node.path }
    }

    /// Selects `url`'s row and scrolls to it. Deselects if `url` is nil, not in the library, or
    /// (without `expandingAncestors`) inside a folder the user collapsed. Folders are expanded
    /// only with `expandingAncestors`, which is for a document change, never a focus change.
    /// Never opens anything.
    func reveal(_ url: URL?, expandingAncestors: Bool = true) {
        loadViewIfNeeded()
        revealing = true
        defer { revealing = false }
        guard let url, let node = Library.shared.tree.node(atPath: LibraryListing.canonicalPath(url)) else {
            outlineView.deselectAll(nil)
            return
        }
        var ancestors: [LibraryNode] = []
        var parent = node.parent
        while let p = parent { ancestors.insert(p, at: 0); parent = p.parent }
        if expandingAncestors { ancestors.forEach { outlineView.expandItem($0) } }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { outlineView.deselectAll(nil); return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: Context menu

    /// Right-click on a location row offers "Remove from Library"; other rows get no menu.
    func menuItems(forRow row: Int) -> [NSMenuItem] {
        guard row >= 0, let node = outlineView.item(atRow: row) as? LibraryNode, node.parent == nil,
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
        guard let node = item as? LibraryNode else { return Library.shared.tree.roots.count }
        node.loadChildren()
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? LibraryNode else { return Library.shared.tree.roots[index] }
        return node.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? LibraryNode)?.isDirectory ?? false
    }

    // MARK: NSOutlineViewDelegate

    /// The user selected a row: a file opens; a folder opens nothing.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !revealing, let node = outlineView.item(atRow: outlineView.selectedRow) as? LibraryNode,
              !node.isDirectory else { return }
        onOpen?(node.url)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? LibraryNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        let icon = NSWorkspace.shared.icon(forFile: node.path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        let missing = node.parent == nil && !FileManager.default.fileExists(atPath: node.path)
        cell.textField?.stringValue = missing ? node.name + " (missing)" : node.name
        cell.textField?.textColor = missing ? .secondaryLabelColor : .labelColor
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
