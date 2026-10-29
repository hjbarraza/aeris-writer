import AppKit
import LibraryCore
import MarkdownCore

/// The table of the file list. Return opens the selected folder and ⌘↑ goes up to the enclosing one.
final class FileListTableView: NSTableView {
    var onReturn: (@MainActor () -> Void)?
    var onEnclosingFolder: (@MainActor () -> Void)?
    /// A ⌘-click or ⌥⌘-click on a row; true if it was taken (the click then selects nothing).
    var onModifiedClick: (@MainActor (_ row: Int, NSEvent.ModifierFlags) -> Bool)?
    /// The right-click menu for a row.
    var menuProvider: (@MainActor (_ row: Int) -> [NSMenuItem])?

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])   // Caps Lock and Fn don't count
        let row = row(at: convert(event.locationInWindow, from: nil))
        if flags.contains(.command), row >= 0, onModifiedClick?(row, flags) == true { return }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let items = menuProvider?(row(at: convert(event.locationInWindow, from: nil))) ?? []
        guard !items.isEmpty else { return super.menu(for: event) }
        // A file row: the tab items, then the list's Sort By / View Options items.
        let menu = NSMenu()
        items.forEach(menu.addItem)
        menu.addItem(.separator())
        FileListMenu.shared.makeItems().forEach(menu.addItem)
        return menu
    }
    /// Right and Left arrows on a folder row (Tree navigation expands and collapses it).
    var onExpand: (@MainActor () -> Bool)?
    var onCollapse: (@MainActor () -> Bool)?

    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) {
        case (36, []), (76, []): onReturn?()
        case (126, .command): onEnclosingFolder?()
        case (124, []) where onExpand?() == true: break
        case (123, []) where onCollapse?() == true: break
        default: super.keyDown(with: event)
        }
    }
}

/// A file row's view: the name, the date on the right and up to two lines of excerpt.
final class FileCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    let excerptLabel = NSTextField(wrappingLabelWithString: "")
    private var nameLeading: NSLayoutConstraint!
    /// Tree navigation: how far the row is pushed in.
    var indent: CGFloat = 0 { didSet { nameLeading.constant = 8 + indent } }

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
        nameLeading = nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            nameLeading,
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

/// A folder row's view: a disclosure button (Tree navigation), the folder icon and the name.
final class FolderCellView: NSTableCellView {
    let expandButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expand")!,
                                target: nil, action: nil)
    private var leading: NSLayoutConstraint!
    private var buttonWidth: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        let image = NSImageView()
        image.contentTintColor = .secondaryLabelColor
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        expandButton.isBordered = false
        expandButton.imagePosition = .imageOnly
        for sub in [expandButton, image, text] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sub)
        }
        imageView = image
        textField = text
        leading = expandButton.leadingAnchor.constraint(equalTo: leadingAnchor)
        buttonWidth = expandButton.widthAnchor.constraint(equalToConstant: 14)
        NSLayoutConstraint.activate([
            leading, buttonWidth,
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.leadingAnchor.constraint(equalTo: expandButton.trailingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: trailingAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Tree navigation shows the disclosure button, indented by the folder's depth; List navigation hides it.
    func configure(tree: Bool, expanded: Bool, depth: Int) {
        expandButton.isHidden = !tree
        buttonWidth.constant = tree ? 14 : 0
        leading.constant = tree ? CGFloat(depth) * 16 : 0
        expandButton.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                     accessibilityDescription: expanded ? "Collapse" : "Expand")
    }
}

/// The dates the sort looks at (modified and created), by path. Read on first use, then kept until
/// `refresh` finds a change. Only reads the file system, never writes.
@MainActor final class SortDateStore {
    private var cache: [String: [Date?]] = [:]
    private let queue = DispatchQueue(label: "aeris.sortdates", qos: .utility)

    nonisolated private static func read(_ path: String) -> [Date?] {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return [v?.contentModificationDate, v?.creationDate]
    }

    /// What is known so far; nil until `refresh` has looked at the file (never stats on the main thread).
    func dates(of node: LibraryNode) -> (modified: Date?, created: Date?)? {
        cache[node.path].map { ($0[0], $0[1]) }
    }

    /// Looks at `paths` off the main thread; `done` runs on the main thread with whether any date is new or moved.
    func refresh(paths: [String], done: @escaping @MainActor (Bool) -> Void) {
        queue.async {
            let fresh = paths.map { ($0, Self.read($0)) }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                var changed = false
                if self.cache.count > 50_000 { self.cache.removeAll() }
                for (path, dates) in fresh where self.cache[path] != dates {
                    self.cache[path] = dates
                    changed = true
                }
                done(changed)
            } }
        }
    }
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
    let created: Date?
    let excerpt: String?
    init(modified: Date?, created: Date?, excerpt: String?) { self.modified = modified; self.created = created; self.excerpt = excerpt }
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
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate, created = values?.creationDate
            let fresh = known.map { $0 == modified } ?? false
            let excerpt = fresh ? nil : Excerpt.ofFile(atPath: path)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self.inFlight.remove(path)
                if !fresh {
                    self.cache.setObject(RowInfo(modified: modified, created: created, excerpt: excerpt), forKey: path as NSString)
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
final class FileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
                                    NSMenuDelegate, NSMenuItemValidation, NSTextFieldDelegate {
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
    private let sortDates = SortDateStore()
    /// A sort by date met a file whose dates are not read yet; the background read re-sorts when it lands.
    private var missingDates = false
    /// Tree navigation: the folders opened inline, by path.
    private var expanded: Set<String> = []
    private var options: FileListOptions { FileListSettings.shared.options }
    let sortBar = NSButton(title: "", target: nil, action: nil)
    private var sortBarHeight: NSLayoutConstraint!
    private let sortMenu = FileListMenu.shared.makeMenu()

    /// Whether file names keep their extension. Off by default; the menu toggle comes later.
    static let showExtensionsKey = "ShowFileExtensions"
    private static let fileRowHeight: CGFloat = 64
    private static let compactFileRowHeight: CGFloat = 32

    /// What the table shows: the folder's children (and, in Tree navigation, those of the folders opened
    /// inline) in sort order, as of the last reload. A disk refresh edits the folder's children before the
    /// list hears of it; row numbers must keep meaning the old rows until then.
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
        tableView.onModifiedClick = { [weak self] row, flags in self?.modifiedClick(row: row, flags: flags) ?? false }
        tableView.menuProvider = { [weak self] row in self?.contextMenuItems(forRow: row) ?? [] }
        tableView.onReturn = { [weak self] in self?.openSelectedFolder() }
        tableView.onEnclosingFolder = { [weak self] in self?.goUp() }
        tableView.onExpand = { [weak self] in self?.expandSelectedFolder(true) ?? false }
        tableView.onCollapse = { [weak self] in self?.expandSelectedFolder(false) ?? false }
        tableView.allowsMultipleSelection = true
        let contextMenu = NSMenu()
        contextMenu.delegate = self  // filled for the clicked row in menuNeedsUpdate
        tableView.menu = contextMenu
        menuNeedsUpdate(contextMenu)
        NotificationCenter.default.addObserver(self, selector: #selector(optionsChanged), name: FileListSettings.didChange, object: nil)
        sortBar.target = self
        sortBar.action = #selector(sortBarClicked(_:))
        sortBar.isBordered = false
        sortBar.font = .systemFont(ofSize: 11)
        sortBar.contentTintColor = .secondaryLabelColor
        sortBar.alignment = .left
        sortBar.imagePosition = .imageTrailing
        sortBar.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: "Sort and view options")
        sortBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        for sub in [upButton, titleLabel, sortBar, scroll, emptyLabel] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        sortBarHeight = sortBar.heightAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([
            sortBarHeight,
            sortBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            sortBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            sortBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            upButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            upButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: sortBar.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
        ])
        view = root
        updateSortBar()
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
        rebuildRows()
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
        expandAncestors(of: path)
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
        let path = url.map(LibraryListing.canonicalPath)
        expandAncestors(of: path)
        revealing = true
        defer { revealing = false }
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
        // A file whose date moved changes the order when the list is sorted by a date.
        refreshSortDates()
    }

    // MARK: Order and options

    private func sorted(_ nodes: [LibraryNode]) -> [LibraryNode] {
        let o = options
        return FileListSort.sorted(nodes, options: o) { node in
            var d: (modified: Date?, created: Date?) = (nil, nil)
            if o.sortKey.isDate {
                if let known = sortDates.dates(of: node) { d = known } else { missingDates = true }
            }
            return FileListSort.Item(name: node.name, isDirectory: node.isDirectory, modified: d.modified, created: d.created)
        }
    }

    /// `rows` from the folder on screen: sorted at every level, with opened folders expanded in place.
    private func rebuildRows() {
        guard let folder else { rows = []; return }
        let tree = options.navigation == .tree
        var result: [LibraryNode] = []
        func add(_ parent: LibraryNode) {
            for child in sorted(parent.children ?? []) {
                result.append(child)
                if tree, child.isDirectory, expanded.contains(child.path) {
                    child.loadChildren()
                    add(child)
                }
            }
        }
        missingDates = false
        add(folder)
        rows = result
        if missingDates { refreshSortDates() }
    }

    private func refreshSortDates() {
        guard options.sortKey.isDate else { return }
        sortDates.refresh(paths: rows.map(\.path)) { [weak self] changed in
            if changed { self?.reloadRows(onlyIfOrderChanged: true) }
        }
    }

    /// Rebuilds and reloads the rows, putting the selection back on the same node; never scrolls or opens anything.
    private func reloadRows(onlyIfOrderChanged: Bool = false) {
        // A reload would take away the name being edited; it runs once the rename ends.
        if renamingNode != nil { reloadAfterRename = true; return }
        let selected = node(atRow: tableView.selectedRow)
        let old = rows
        rebuildRows()
        if onlyIfOrderChanged, old.count == rows.count, zip(old, rows).allSatisfy({ $0 === $1 }) { return }
        let wasRevealing = revealing
        revealing = true
        tableView.reloadData()
        if let selected, let row = rows.firstIndex(where: { $0 === selected }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            // The highlighted file is gone: no neighbour inherits its row.
            tableView.deselectAll(nil)
        }
        revealing = wasRevealing
    }

    @objc private func optionsChanged() {
        updateSortBar()
        reloadRows()
        refreshSortDates()
    }

    private func updateSortBar() {
        let o = options
        sortBar.title = "\(o.sortTitle), \(o.directionTitle)"
        sortBar.isHidden = !o.showSortBar
        sortBarHeight.constant = o.showSortBar ? 20 : 0
    }

    @objc private func sortBarClicked(_ sender: NSButton) {
        sortMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    private func setExpanded(_ node: LibraryNode, _ on: Bool) {
        guard options.navigation == .tree, node.isDirectory,
              expanded.contains(node.path) != on else { return }
        if on { expanded.insert(node.path) } else { expanded.remove(node.path) }
        reloadRows()
    }

    /// Right and Left arrows: true if the selected folder row took the key.
    private func expandSelectedFolder(_ on: Bool) -> Bool {
        guard options.navigation == .tree, let node = node(atRow: tableView.selectedRow) else { return false }
        if node.isDirectory, expanded.contains(node.path) != on {
            setExpanded(node, on)
            return true
        }
        // Left on a file, a closed folder or a nested row goes to the enclosing folder's row.
        guard !on, let parent = node.parent, parent !== folder, let row = rows.firstIndex(where: { $0 === parent }) else { return false }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        return true
    }

    /// Tree navigation: opens the folders between the folder on screen and `path`, so its row is there.
    private func expandAncestors(of path: String?) {
        guard options.navigation == .tree, let folder, let path, path.hasPrefix(folder.path + "/") else { return }
        var changed = false
        var up = Library.shared.tree.node(atPath: path)?.parent
        while let p = up, p !== folder {
            changed = expanded.insert(p.path).inserted || changed
            up = p.parent
        }
        if changed { reloadRows() }
    }

    @objc private func disclosureClicked(_ sender: NSButton) {
        guard let node = node(atRow: tableView.row(for: sender)) else { return }
        setExpanded(node, !expanded.contains(node.path))
    }

    private func depth(of node: LibraryNode) -> Int {
        var depth = 0, up = node.parent
        while let p = up, p !== folder { depth += 1; up = p.parent }
        return depth
    }

    private func infoLoaded(_ path: String) {
        guard let row = rows.firstIndex(where: { $0.path == path }),
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileCellView else { return }
        show(infos.info(path: path), in: cell)
    }

    /// The date, and the excerpt: "No text" for an empty file, nothing for an unreadable one
    /// or while it is being read.
    private func show(_ info: RowInfo?, in cell: FileCellView) {
        let date: Date? = switch options.showDate {
        case .modified: info?.modified
        case .created: info?.created
        case .none: nil
        }
        cell.dateLabel.stringValue = date.map { dates.label(for: $0) } ?? ""
        cell.excerptLabel.isHidden = !options.showExcerpts
        cell.excerptLabel.stringValue = info?.excerpt.map { $0.isEmpty ? "No text" : $0 } ?? ""
    }

    /// A disk refresh changed the tree: reload if the folder on screen changed, and follow it
    /// if the folder itself was replaced or is gone. The selection is put back; the view never scrolls.
    func apply(_ changes: [TreeChange]) {
        guard let folder else { return }
        if Library.shared.tree.node(atPath: folder.path) !== folder {
            return showFolder(Library.shared.tree.node(atPath: folder.path))
        }
        guard changes.contains(where: { change in change.parent === folder || rows.contains { $0 === change.parent } }) else { return }
        reloadRows()
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

    /// The selected folder row: Tree navigation opens or closes it in place, List navigation shows its
    /// contents here. A file row does nothing here.
    private func openSelectedFolder() {
        guard let node = node(atRow: tableView.selectedRow), node.isDirectory else { return }
        if options.navigation == .tree {
            setExpanded(node, !expanded.contains(node.path))
        } else {
            showFolder(node)
            onNavigate?()
        }
    }

    @objc private func rowDoubleClicked(_ sender: Any?) { openSelectedFolder() }
    @objc private func upClicked(_ sender: Any?) { goUp() }

    // MARK: Opening

    /// Set by the window controller: opens a file in a new tab of this window, or in a window of its own.
    var onOpenElsewhere: (@MainActor (URL, _ asTab: Bool) -> Void)?

    /// The right-click menu of a file row; folders and empty space have none.
    func contextMenuItems(forRow row: Int) -> [NSMenuItem] {
        guard let node = node(atRow: row), !node.isDirectory else { return [] }
        return [
            BlockMenuItem("Open in New Tab") { [weak self] in self?.onOpenElsewhere?(node.url, true) },
            BlockMenuItem("Open in New Window") { [weak self] in self?.onOpenElsewhere?(node.url, false) },
        ]
    }

    /// ⌘-click opens a file row in a new tab, ⌥⌘-click in a new window.
    private func modifiedClick(row: Int, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags == [.command] || flags == [.command, .option], let node = node(atRow: row), !node.isDirectory else { return false }
        onOpenElsewhere?(node.url, !flags.contains(.option))
        return true
    }

    /// A row was clicked: a file opens and the editor takes the keyboard.
    @objc private func rowClicked(_ sender: Any?) {
        guard tableView.selectedRowIndexes.count == 1, let node = node(atRow: tableView.selectedRow), !node.isDirectory else { return }
        onOpen?(node.url, true)
    }

    /// The selection moved (arrow keys, or the click's own selection): a file opens, focus stays.
    func tableViewSelectionDidChange(_ notification: Notification) {
        if !revealing { onStateChange?() }
        // Several rows selected: nothing opens.
        guard !revealing, tableView.selectedRowIndexes.count == 1,
              let node = node(atRow: tableView.selectedRow), !node.isDirectory else { return }
        onOpen?(node.url, false)
    }

    // MARK: File operations

    /// What a file command acts on: the right-clicked row (or the selection, if the click was in
    /// it) for the context menu, the selection for the File menu. `clicked` decides where new
    /// items go: into a clicked folder, beside a clicked file, else into the folder on screen.
    private final class Targets: NSObject {
        let nodes: [LibraryNode]
        let clicked: LibraryNode?
        init(nodes: [LibraryNode], clicked: LibraryNode?) { self.nodes = nodes; self.clicked = clicked }
    }

    /// The file commands, routed here from the File menu whatever has focus in the window.
    static let fileActions: Set<Selector> = [
        #selector(newFile(_:)), #selector(newFolder(_:)), #selector(newFolderWithSelection(_:)),
        #selector(renameItem(_:)), #selector(duplicateItems(_:)), #selector(trashItems(_:)),
        #selector(deleteItemsImmediately(_:)), #selector(showItemsInFinder(_:)),
    ]

    /// The row whose name is being edited, and its text field.
    private(set) var renamingNode: LibraryNode?
    private(set) var renameField: NSTextField?
    private var reloadAfterRename = false
    private var sharePicker: NSSharingServicePicker?

    private func targets(_ sender: Any?) -> Targets {
        if let targets = (sender as? NSMenuItem)?.representedObject as? Targets { return targets }
        return Targets(nodes: tableView.selectedRowIndexes.compactMap(node(atRow:)), clicked: nil)
    }

    private func destination(_ targets: Targets) -> LibraryNode? {
        guard let clicked = targets.clicked else { return folder }
        return clicked.isDirectory ? clicked : clicked.parent
    }

    /// The context menu for a right-click on `row` (-1: the empty area).
    func contextMenu(forClickedRow row: Int) -> NSMenu {
        let clicked = node(atRow: row)
        let selection = tableView.selectedRowIndexes
        let nodes = clicked == nil ? [] : selection.contains(row) ? selection.compactMap(node(atRow:)) : [clicked!]
        let targets = Targets(nodes: nodes, clicked: clicked)
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, alternate: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = targets
            if alternate { item.keyEquivalentModifierMask = .option; item.isAlternate = true }
            menu.addItem(item)
        }
        add("New File", #selector(newFile(_:)))
        add("New Folder", #selector(newFolder(_:)))
        add("New Folder with Selection", #selector(newFolderWithSelection(_:)))
        menu.addItem(.separator())
        add("Rename", #selector(renameItem(_:)))
        add("Duplicate", #selector(duplicateItems(_:)))
        add("Move to Trash", #selector(trashItems(_:)))
        add("Delete Immediately…", #selector(deleteItemsImmediately(_:)), alternate: true)
        menu.addItem(.separator())
        add("Show in Finder", #selector(showItemsInFinder(_:)))
        if !nodes.isEmpty {
            let picker = NSSharingServicePicker(items: nodes.map(\.url))
            sharePicker = picker
            menu.addItem(picker.standardShareMenuItem)
        }
        menu.addItem(.separator())
        FileListMenu.shared.makeItems().forEach(menu.addItem)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === tableView.menu else { return }
        let fresh = contextMenu(forClickedRow: tableView.clickedRow)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let t = targets(item)
        switch item.action {
        case #selector(newFile(_:)), #selector(newFolder(_:)): return destination(t) != nil
        case #selector(newFolderWithSelection(_:)): return t.nodes.count > 1
        case #selector(renameItem(_:)): return t.nodes.count == 1
        case #selector(duplicateItems(_:)), #selector(trashItems(_:)), #selector(deleteItemsImmediately(_:)),
             #selector(showItemsInFinder(_:)): return !t.nodes.isEmpty
        default: return true
        }
    }

    @objc func newFile(_ sender: Any?) { create(in: destination(targets(sender)), base: "Untitled", ext: "md", isFolder: false) }
    @objc func newFolder(_ sender: Any?) { create(in: destination(targets(sender)), base: "untitled folder", ext: "", isFolder: true) }

    private func create(in parent: LibraryNode?, base: String, ext: String, isFolder: Bool) {
        guard let parent else { return }
        let dir = parent.url
        FileOperations.run({
            FileOperations.each([FileOperations.freeURL(in: dir, base: base, ext: ext)]) { url in
                if isFolder { try FileOperations.createFolder(at: url) } else { try FileOperations.createFile(at: url) }
                return url
            }
        }) { [weak self] outcome in
            self?.finish(outcome, failure: "The new item could not be made.", changed: [parent], select: true, rename: true)
        }
    }

    @objc func newFolderWithSelection(_ sender: Any?) {
        let nodes = targets(sender).nodes
        guard nodes.count > 1, let parent = nodes[0].parent else { return }
        let dir = parent.url, urls = nodes.map(\.url)
        FileOperations.run({
            let folder = FileOperations.freeURL(in: dir, base: "New Folder With Items", ext: "")
            var outcome = FileOperations.each([folder]) { try FileOperations.createFolder(at: $0); return $0 }
            guard outcome.failures.isEmpty else { return outcome }
            outcome.failures = FileOperations.each(urls) { try FileOperations.move($0, to: folder.appending(path: $0.lastPathComponent)); return nil }.failures
            return outcome
        }) { [weak self] outcome in
            self?.finish(outcome, failure: "Some items could not be moved to the new folder.",
                         changed: [parent] + nodes.compactMap(\.parent), select: true, rename: true)
        }
    }

    @objc func duplicateItems(_ sender: Any?) {
        let nodes = targets(sender).nodes
        FileOperations.run({ [urls = nodes.map(\.url)] in
            FileOperations.each(urls) { url in
                let copy = FileOperations.freeURL(in: url.deletingLastPathComponent(),
                                                  base: url.deletingPathExtension().lastPathComponent + " copy", ext: url.pathExtension)
                try FileOperations.copy(url, to: copy)
                return copy
            }
        }) { [weak self] outcome in
            self?.finish(outcome, failure: "Some items could not be duplicated.", changed: nodes.compactMap(\.parent), select: true)
        }
    }

    @objc func trashItems(_ sender: Any?) {
        let nodes = targets(sender).nodes
        FileOperations.run({ [urls = nodes.map(\.url)] in FileOperations.each(urls, FileOperations.trash) }) { [weak self] outcome in
            self?.finish(outcome, failure: "Some items could not be moved to the Trash.", changed: nodes.compactMap(\.parent))
        }
    }

    /// Option-Move to Trash: deletes for good, once the user confirms.
    @objc func deleteItemsImmediately(_ sender: Any?) {
        let nodes = targets(sender).nodes
        guard !nodes.isEmpty else { return }
        let what = nodes.count == 1 ? "“\(nodes[0].name)”" : "these \(nodes.count) items"
        FileOperations.confirmDelete("Are you sure you want to delete \(what) immediately?", view.window) { [weak self] delete in
            guard delete else { return }
            FileOperations.run({ [urls = nodes.map(\.url)] in FileOperations.each(urls) { try FileOperations.delete($0); return nil } }) { outcome in
                self?.finish(outcome, failure: "Some items could not be deleted.", changed: nodes.compactMap(\.parent))
            }
        }
    }

    @objc func showItemsInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting(targets(sender).nodes.map(\.url))
    }

    /// After an operation: re-lists the folders it touched, selects what it made (bringing it on
    /// screen), optionally starts renaming it, and shows every failure in one alert.
    private func finish(_ outcome: FileOperations.Outcome, failure: String, changed: [LibraryNode],
                        select: Bool = false, rename: Bool = false) {
        Library.shared.folderChanged(Set(changed.map(\.path)).map { FolderChange(path: $0, mustScanSubDirs: false, rootChanged: false) })
        let made = outcome.made.map(LibraryListing.canonicalPath)
        if select, let first = made.first {
            expandAncestors(of: first)
            if !rows.contains(where: { $0.path == first }), let parent = Library.shared.tree.node(atPath: first)?.parent {
                showFolder(parent)
                onNavigate?()
            }
            let indexes = IndexSet(made.compactMap { path in rows.firstIndex { $0.path == path } })
            revealing = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            revealing = false
            if let row = indexes.first { tableView.scrollRowToVisible(row) }
            if rename, made.count == 1, let node = rows.first(where: { $0.path == first }) { beginRename(node) }
        }
        if !outcome.failures.isEmpty { FileOperations.presentFailures(failure, outcome.failures, view.window) }
    }

    @objc func renameItem(_ sender: Any?) {
        guard let node = targets(sender).nodes.first else { return }
        beginRename(node)
    }

    /// Edits the row's name in place, the name selected without its extension.
    private func beginRename(_ node: LibraryNode) {
        finishRename(commit: true)
        guard let row = rows.firstIndex(where: { $0 === node }) else { return }
        revealing = true
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        revealing = false
        tableView.scrollRowToVisible(row)
        guard let field = (tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField else { return }
        renamingNode = node
        renameField = field
        field.stringValue = node.name
        field.isEditable = true
        field.delegate = self
        view.window?.makeFirstResponder(field)
        let base = node.isDirectory ? node.name : (node.name as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    /// Return commits, Esc restores; leaving the field (a click elsewhere) commits too.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === renameField else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): finishRename(commit: false)
        case #selector(NSResponder.insertNewline(_:)): finishRename(commit: true)
        default: return false
        }
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if notification.object as? NSTextField === renameField { finishRename(commit: true) }
    }

    /// Ends the rename. An empty or unchanged name does nothing; the row shows its name as before
    /// until the disk says otherwise.
    private func finishRename(commit: Bool) {
        guard let node = renamingNode, let field = renameField else { return }
        let typed = field.stringValue
        let editing = field.currentEditor() != nil
        renamingNode = nil
        renameField = nil
        field.abortEditing()
        field.delegate = nil
        field.isEditable = false
        let showExtension = node.isDirectory || AppDefaults.store.bool(forKey: Self.showExtensionsKey)
        field.stringValue = showExtension ? node.name : (node.name as NSString).deletingPathExtension
        // Return or Esc gives the keyboard back to the list; a click elsewhere already moved it.
        if editing { view.window?.makeFirstResponder(tableView) }
        if reloadAfterRename {
            reloadAfterRename = false
            reloadRows()
        }
        guard commit, !typed.isEmpty, typed != node.name, let parent = node.parent else { return }
        guard !typed.contains("/") else {
            let error = CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "A name can’t contain “/”."])
            return FileOperations.presentFailures("“\(node.name)” could not be renamed.", [.init(url: node.url, error: error)], view.window)
        }
        let source = node.url, target = source.deletingLastPathComponent().appending(path: typed)
        let wasOpen = openPath == node.path
        FileOperations.run({ FileOperations.each([source]) { try FileOperations.move($0, to: target); return target } }) { [weak self] outcome in
            guard let self else { return }
            if wasOpen, let moved = outcome.made.first { setOpenPath(LibraryListing.canonicalPath(moved)) }
            finish(outcome, failure: "“\(node.name)” could not be renamed.", changed: [parent], select: true)
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        node(atRow: row)?.isDirectory == false
            ? (options.showExcerpts ? Self.fileRowHeight : Self.compactFileRowHeight) : tableView.rowHeight
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
        let id = NSUserInterfaceItemIdentifier("folderCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FolderCellView ?? makeFolderCell(id)
        cell.configure(tree: options.navigation == .tree, expanded: expanded.contains(node.path), depth: depth(of: node))
        cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
        cell.textField?.stringValue = node.name
        return cell
    }

    private func fileCell(for node: LibraryNode) -> FileCellView {
        let id = NSUserInterfaceItemIdentifier("fileCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileCellView ?? FileCellView()
        cell.identifier = id
        let showExtension = AppDefaults.store.bool(forKey: Self.showExtensionsKey)
        cell.indent = options.navigation == .tree ? CGFloat(depth(of: node)) * 16 : 0
        cell.nameLabel.stringValue = showExtension ? node.name : (node.name as NSString).deletingPathExtension
        show(infos.info(path: node.path), in: cell)
        infos.refresh(path: node.path)
        return cell
    }

    private func makeFolderCell(_ id: NSUserInterfaceItemIdentifier) -> FolderCellView {
        let cell = FolderCellView()
        cell.identifier = id
        cell.expandButton.target = self
        cell.expandButton.action = #selector(disclosureClicked(_:))
        return cell
    }
}
