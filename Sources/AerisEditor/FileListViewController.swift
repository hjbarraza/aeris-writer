import AppKit
import LibraryCore

/// The file list: the files and subfolders of the folder selected in the sidebar, under a
/// title that names the folder. Rows are the folder's own `LibraryNode` children, so the live
/// refresh that edits the tree updates this list too.
final class FileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = NSTableView()
    let titleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Select a folder to see its files.")
    private(set) var folder: LibraryNode?
    /// Set by the window controller: opens a file row. `focusEditor` is true for a click and
    /// false for the arrow keys, which keep the keyboard in the list.
    var onOpen: (@MainActor (URL, _ focusEditor: Bool) -> Void)?
    /// A programmatic selection is in progress; it never opens anything.
    private var revealing = false

    private var rows: [LibraryNode] { folder?.children ?? [] }

    func node(atRow row: Int) -> LibraryNode? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    override func loadView() {
        tableView.style = .inset
        tableView.headerView = nil
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let root = NSView()
        for sub in [titleLabel, scroll, emptyLabel] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
        ])
        view = root
        Library.shared.register(self)
        showFolder(folder)
    }

    /// Lists `node`'s children (nothing for nil or a file). Showing the folder already on
    /// screen leaves the selection alone.
    func showFolder(_ node: LibraryNode?) {
        loadViewIfNeeded()
        let node = node?.isDirectory == true ? node : nil
        if node != nil, node === folder { return }
        folder = node
        node?.loadChildren()
        titleLabel.stringValue = node?.name ?? ""
        emptyLabel.isHidden = node != nil
        revealing = true
        tableView.reloadData()
        revealing = false
    }

    /// Selects `url`'s row if it is in the folder on screen; otherwise clears the selection.
    /// Never opens anything.
    func reveal(_ url: URL?) {
        loadViewIfNeeded()
        revealing = true
        defer { revealing = false }
        let path = url.map(LibraryListing.canonicalPath)
        guard let row = rows.firstIndex(where: { $0.path == path }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    /// A disk refresh changed the tree: reload if the folder on screen changed, and follow it
    /// if the folder itself was replaced or is gone. The selection is put back; the view never scrolls.
    func apply(_ changes: [TreeChange]) {
        guard let folder else { return }
        if Library.shared.tree.node(atPath: folder.path) !== folder {
            return showFolder(Library.shared.tree.node(atPath: folder.path))
        }
        guard changes.contains(where: { $0.parent === folder }) else { return }
        let selected = node(atRow: tableView.selectedRow)
        revealing = true
        tableView.reloadData()
        if let selected, let row = rows.firstIndex(where: { $0 === selected }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
        revealing = false
    }

    /// The library's roots changed: the folder on screen may be gone or replaced.
    func libraryRootsDidChange() {
        guard let folder else { return }
        let current = Library.shared.tree.node(atPath: folder.path)
        self.folder = nil  // force a reload even if the node is the same
        showFolder(current)
    }

    // MARK: Opening

    /// A row was clicked: a file opens and the editor takes the keyboard.
    @objc private func rowClicked(_ sender: Any?) {
        guard let node = node(atRow: tableView.selectedRow), !node.isDirectory else { return }
        onOpen?(node.url, true)
    }

    /// The selection moved (arrow keys, or the click's own selection): a file opens, focus stays.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !revealing, let node = node(atRow: tableView.selectedRow), !node.isDirectory else { return }
        onOpen?(node.url, false)
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let node = node(atRow: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        cell.imageView?.image = NSImage(systemSymbolName: node.isDirectory ? "folder" : "doc.text",
                                        accessibilityDescription: node.isDirectory ? "Folder" : "Document")
        cell.textField?.stringValue = node.name
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        image.contentTintColor = .secondaryLabelColor
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
