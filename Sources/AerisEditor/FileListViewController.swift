import AppKit
import LibraryCore

/// The table of the file list. Return opens the selected folder and ⌘↑ goes up to the enclosing one.
final class FileListTableView: NSTableView {
    var onReturn: (@MainActor () -> Void)?
    var onEnclosingFolder: (@MainActor () -> Void)?

    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) {
        case (36, []), (76, []): onReturn?()
        case (126, .command): onEnclosingFolder?()
        default: super.keyDown(with: event)
        }
    }
}

/// The file list: the files and subfolders of the location selected in the organizer, under a
/// title that names the folder. Double-click or Return on a folder row opens it here; the
/// button left of the title and ⌘↑ go back up. Rows are the folder's own `LibraryNode`
/// children, so the live refresh that edits the tree updates this list too.
final class FileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = FileListTableView()
    let titleLabel = NSTextField(labelWithString: "")
    let upButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Enclosing Folder")!,
                            target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "Select a folder to see its files.")
    private(set) var folder: LibraryNode?
    /// Set by the window controller: opens a file row. `focusEditor` is true for a click and
    /// false for the arrow keys, which keep the keyboard in the list.
    var onOpen: (@MainActor (URL, _ focusEditor: Bool) -> Void)?
    /// Set by the window controller: the list moved to another folder by itself (not because
    /// the organizer asked), so the open document's row can be highlighted if it is here.
    var onNavigate: (@MainActor () -> Void)?
    /// A programmatic selection is in progress; it never opens anything.
    private var revealing = false

    /// What the table shows: the folder's children as of the last reload. A disk refresh edits the
    /// folder's children before the list hears of it; row numbers must keep meaning the old rows until then.
    private var rows: [LibraryNode] = []

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
        tableView.doubleAction = #selector(rowDoubleClicked(_:))
        tableView.onReturn = { [weak self] in self?.openSelectedFolder() }
        tableView.onEnclosingFolder = { [weak self] in self?.goUp() }
        upButton.target = self
        upButton.action = #selector(upClicked(_:))
        upButton.isBordered = false
        upButton.toolTip = "Enclosing Folder (⌘↑)"
        upButton.isEnabled = false

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let root = NSView()
        for sub in [upButton, titleLabel, scroll, emptyLabel] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            upButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            upButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 6),
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
        rows = node?.children ?? []
        titleLabel.stringValue = node?.name ?? ""
        upButton.isEnabled = node?.parent != nil
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
        rows = folder.children ?? []
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

    // MARK: Walking folders

    /// Shows `folder`'s parent (a location has none), then selects the folder it came from.
    func goUp() {
        guard let came = folder, let parent = came.parent else { return }
        showFolder(parent)
        if let row = rows.firstIndex(where: { $0 === came }) {
            revealing = true
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            revealing = false
        }
    }

    /// Shows the selected folder row's contents; a file row does nothing here.
    private func openSelectedFolder() {
        guard let node = node(atRow: tableView.selectedRow), node.isDirectory else { return }
        showFolder(node)
        onNavigate?()
    }

    @objc private func rowDoubleClicked(_ sender: Any?) { openSelectedFolder() }
    @objc private func upClicked(_ sender: Any?) { goUp() }

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
