import AppKit
import LibraryCore
import MarkdownCore

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

/// A file row's view: the name, the date on the right and up to two lines of excerpt.
final class FileCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    let excerptLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabelColor
        excerptLabel.font = .systemFont(ofSize: 12)
        excerptLabel.textColor = .secondaryLabelColor
        excerptLabel.maximumNumberOfLines = 2
        excerptLabel.lineBreakMode = .byTruncatingTail
        excerptLabel.isSelectable = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for sub in [nameLabel, dateLabel, excerptLabel] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sub)
        }
        textField = nameLabel
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            dateLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            excerptLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            excerptLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            excerptLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// A row; the document open in this window gets a bar at its leading edge, whatever is selected.
final class FileRowView: NSTableRowView {
    var showsOpenMarker = false { didSet { if showsOpenMarker != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsOpenMarker else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 4, width: 3, height: bounds.height - 8), xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// What a file row shows besides its name: the modification date and the excerpt
/// (nil when the file can't be read as text).
final class RowInfo: NSObject {
    let modified: Date?
    let excerpt: String?
    init(modified: Date?, excerpt: String?) { self.modified = modified; self.excerpt = excerpt }
}

/// Row info of the files on screen. The stat and the read happen off the main thread; the result
/// is kept (bounded) until the modification date changes. Only reads user files, never writes them.
@MainActor final class RowInfoStore {
    private let cache = NSCache<NSString, RowInfo>()
    private var inFlight: Set<String> = []
    private var again: Set<String> = []
    private let queue = DispatchQueue(label: "aeris.rowinfo", qos: .utility)
    /// Called on the main thread with the path of a file whose info just changed.
    var onLoaded: (@MainActor (String) -> Void)?

    init() { cache.countLimit = 5000 }

    /// What is known about `path` so far, possibly stale.
    func info(path: String) -> RowInfo? { cache.object(forKey: path as NSString) }

    /// Checks the file in the background; `onLoaded` fires only if its date changed or it is new.
    func refresh(path: String) {
        guard inFlight.insert(path).inserted else { again.insert(path); return }
        let known: Date?? = info(path: path).map { $0.modified }
        queue.async {
            let modified = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let fresh = known.map { $0 == modified } ?? false
            let excerpt = fresh ? nil : Excerpt.ofFile(atPath: path)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self.inFlight.remove(path)
                if !fresh {
                    self.cache.setObject(RowInfo(modified: modified, excerpt: excerpt), forKey: path as NSString)
                    self.onLoaded?(path)
                }
                if self.again.remove(path) != nil { self.refresh(path: path) }
            } }
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
    /// Set by the window controller: the folder or the selection changed (window state to save).
    var onStateChange: (@MainActor () -> Void)?
    /// A programmatic selection is in progress; it never opens anything.
    private var revealing = false
    /// Canonical path of the document open in this window; its row carries the marker.
    private var openPath: String?
    private let infos = RowInfoStore()
    private let dates = RowDateFormatter()

    /// Whether file names keep their extension. Off by default; the menu toggle comes later.
    static let showExtensionsKey = "ShowFileExtensions"
    private static let fileRowHeight: CGFloat = 64

    /// What the table shows: the folder's children as of the last reload. A disk refresh edits the
    /// folder's children before the list hears of it; row numbers must keep meaning the old rows until then.
    private var rows: [LibraryNode] = []

    func node(atRow row: Int) -> LibraryNode? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    override func loadView() {
        tableView.style = .inset
        infos.onLoaded = { [weak self] path in self?.infoLoaded(path) }
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
        onStateChange?()
    }

    /// Path of the selected row (a file or a folder), nil if nothing is selected.
    var selectedPath: String? { node(atRow: tableView.selectedRow)?.path }

    /// Selects the row at `path` if it is in the folder on screen, otherwise clears the selection.
    /// Restoring a window's state: never opens anything.
    func restoreSelection(path: String?) {
        loadViewIfNeeded()
        revealing = true
        defer { revealing = false }
        guard let path, let row = rows.firstIndex(where: { $0.path == path }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    /// Selects `url`'s row if it is in the folder on screen; otherwise clears the selection.
    /// Never opens anything.
    func reveal(_ url: URL?) {
        loadViewIfNeeded()
        revealing = true
        defer { revealing = false }
        let path = url.map(LibraryListing.canonicalPath)
        setOpenPath(path)
        guard let row = rows.firstIndex(where: { $0.path == path }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func setOpenPath(_ path: String?) {
        guard path != openPath else { return }
        let old = openPath
        openPath = path
        for changed in [old, path].compactMap({ $0 }) {
            guard let row = rows.firstIndex(where: { $0.path == changed }) else { continue }
            (tableView.rowView(atRow: row, makeIfNecessary: false) as? FileRowView)?.showsOpenMarker = changed == path
        }
    }

    /// The date and excerpt of a file changed on disk: look again at the rows on screen. A disk event
    /// or a save of the open document calls this; the store only re-reads files whose date moved.
    func refreshVisibleRows() {
        let visible = tableView.rows(in: tableView.visibleRect)
        for row in visible.location..<(visible.location + visible.length) where rows.indices.contains(row) && !rows[row].isDirectory {
            infos.refresh(path: rows[row].path)
        }
    }

    private func infoLoaded(_ path: String) {
        guard let row = rows.firstIndex(where: { $0.path == path }),
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileCellView else { return }
        show(infos.info(path: path), in: cell)
    }

    /// The date, and the excerpt: "No text" for an empty file, nothing for an unreadable one
    /// or while it is being read.
    private func show(_ info: RowInfo?, in cell: FileCellView) {
        cell.dateLabel.stringValue = info?.modified.map { dates.label(for: $0) } ?? ""
        cell.excerptLabel.stringValue = info?.excerpt.map { $0.isEmpty ? "No text" : $0 } ?? ""
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
        } else {
            // The highlighted file is gone: no neighbour inherits its row.
            tableView.deselectAll(nil)
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

    /// Shows `folder`'s parent (a location has none), then highlights the open document if it is
    /// there, otherwise the folder it came from.
    func goUp() {
        guard let came = folder, let parent = came.parent else { return }
        showFolder(parent)
        onNavigate?()
        if tableView.selectedRow < 0, let row = rows.firstIndex(where: { $0 === came }) {
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
        if !revealing { onStateChange?() }
        guard !revealing, let node = node(atRow: tableView.selectedRow), !node.isDirectory else { return }
        onOpen?(node.url, false)
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        node(atRow: row)?.isDirectory == false ? Self.fileRowHeight : tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = tableView.makeView(withIdentifier: id, owner: nil) as? FileRowView ?? FileRowView()
        view.identifier = id
        view.showsOpenMarker = openPath != nil && node(atRow: row)?.path == openPath
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let node = node(atRow: row) else { return nil }
        if !node.isDirectory { return fileCell(for: node) }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
        cell.textField?.stringValue = node.name
        return cell
    }

    private func fileCell(for node: LibraryNode) -> FileCellView {
        let id = NSUserInterfaceItemIdentifier("fileCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileCellView ?? FileCellView()
        cell.identifier = id
        let showExtension = AppDefaults.store.bool(forKey: Self.showExtensionsKey)
        cell.nameLabel.stringValue = showExtension ? node.name : (node.name as NSString).deletingPathExtension
        show(infos.info(path: node.path), in: cell)
        infos.refresh(path: node.path)
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
