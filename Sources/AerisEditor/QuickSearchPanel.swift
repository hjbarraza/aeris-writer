import AppKit
import LibraryCore

/// The floating panel behind Go > Quick Search (⇧⌘O). Typing ranks the files of every location by
/// name; Return opens the selected one in the window it was opened from, Esc gives the keyboard
/// back to where it was. Names are enumerated off the main thread when the panel opens (no index),
/// and any new input cancels the ranking still running for the old one.
@MainActor
final class QuickSearchController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickSearchController()

    private static let width: CGFloat = 560, fieldHeight: CGFloat = 52, rowHeight: CGFloat = 40, maxRows = 8

    /// Built once and reused; `panel` is it only while it is on screen.
    private var window: QuickSearchPanel?
    private var onScreen = false
    var panel: QuickSearchPanel? { onScreen ? window : nil }
    private(set) var results: [QuickSearch.Result] = []
    private let field = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    private var candidates: [QuickSearch.Candidate] = []
    private var generation = 0
    private var enumeration: Task<Void, Never>?
    private var ranking: Task<Void, Never>?
    private weak var parent: NSWindow?
    private weak var previousResponder: NSResponder?
    private var openFile: ((URL) -> Void)?

    var isShown: Bool { panel != nil }
    var query: String { field.stringValue }

    // MARK: Showing and closing

    /// Opens the panel over `window` and starts listing the library. `open` receives the chosen file.
    func show(over window: NSWindow, open: @escaping (URL) -> Void) {
        if isShown { close(restoreFocus: false) }
        parent = window
        previousResponder = window.firstResponder
        openFile = open
        candidates = []
        results = []
        generation += 1
        let panel = self.window ?? QuickSearchPanel(controller: self)
        if self.window == nil { build(in: panel); self.window = panel }
        onScreen = true
        field.stringValue = ""
        table.reloadData()
        layoutPanel()
        if window.isVisible {
            window.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(field)
        }
        startEnumeration(roots: Library.shared.tree.roots.map(\.url))
    }

    /// Closes the panel. Esc and a chosen result put the keyboard back where it was.
    func close(restoreFocus: Bool = true) {
        guard let panel else { return }
        generation += 1
        enumeration?.cancel(); ranking?.cancel()
        onScreen = false
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoreFocus, let parent {
            parent.makeKeyAndOrderFront(nil)
            parent.makeFirstResponder(previousResponder ?? parent)
        }
    }

    private func startEnumeration(roots: [URL]) {
        let gen = generation
        enumeration = Task.detached(priority: .userInitiated) { [weak self] in
            QuickSearch.enumerate(roots: roots, isCancelled: { Task.isCancelled }) { batch in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.add(batch, generation: gen) }
                }
            }
        }
    }

    private func add(_ batch: [QuickSearch.Candidate], generation gen: Int) {
        guard gen == generation, isShown else { return }
        candidates += batch
        rerank()
    }

    // MARK: Ranking

    /// Types `text` into the field, as the user would.
    func setQuery(_ text: String) {
        field.stringValue = text
        rerank()
    }

    func controlTextDidChange(_ obj: Notification) { rerank() }

    private func rerank() {
        ranking?.cancel()
        let query = field.stringValue, snapshot = candidates, gen = generation
        let showExtension = AppDefaults.store.bool(forKey: FileListViewController.showExtensionsKey)
        ranking = Task.detached(priority: .userInitiated) { [weak self] in
            let ranked = QuickSearch.rank(query: query, candidates: snapshot, showExtension: showExtension)
            if Task.isCancelled { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(ranked, generation: gen) }
            }
        }
    }

    private func apply(_ ranked: [QuickSearch.Result], generation gen: Int) {
        guard gen == generation, isShown else { return }
        results = ranked
        table.reloadData()
        if !ranked.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        layoutPanel()
    }

    // MARK: Choosing

    /// Opens the selected result (the first if none is selected) and closes the panel.
    func openSelected() {
        guard !results.isEmpty else { return }
        let row = table.selectedRow >= 0 ? table.selectedRow : 0
        let url = URL(fileURLWithPath: results[row].candidate.path)
        let open = openFile
        close()
        open?(url)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), results.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    @objc private func rowClicked(_ sender: Any?) {
        if table.clickedRow >= 0 { openSelected() }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("quickSearchCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? QuickSearchCell ?? QuickSearchCell()
        cell.identifier = id
        cell.show(results[row])
        return cell
    }

    // MARK: Layout

    private func build(in panel: QuickSearchPanel) {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        panel.contentView = background

        field.placeholderString = "Search files"
        field.font = .systemFont(ofSize: 18)
        field.delegate = self
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.refusesFirstResponder = true
        table.target = self
        table.action = #selector(rowClicked(_:))
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false

        for v in [field, rule, scroll] as [NSView] { background.addSubview(v) }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            field.heightAnchor.constraint(equalToConstant: Self.fieldHeight - 20),
            rule.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.fieldHeight),
            rule.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
    }

    /// Sizes the panel to its results (field only when there are none) and keeps it centred near
    /// the top of the window it belongs to.
    private func layoutPanel() {
        guard let panel, let parent else { return }
        let rows = min(results.count, Self.maxRows)
        let height = Self.fieldHeight + (rows == 0 ? 0 : CGFloat(rows) * Self.rowHeight + 4)
        let frame = parent.frame
        panel.setFrame(NSRect(x: frame.midX - Self.width / 2, y: frame.maxY - 90 - height,
                              width: Self.width, height: height), display: true)
    }
}

/// Borderless and able to take the keyboard; Esc closes it.
final class QuickSearchPanel: NSPanel {
    private unowned let controller: QuickSearchController

    @MainActor init(controller: QuickSearchController) {
        self.controller = controller
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 52),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { controller.close() }
    }

    /// Clicking elsewhere dismisses the panel without moving the keyboard.
    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated {
            if controller.panel === self { controller.close(restoreFocus: false) }
        }
    }
}

/// A result row: the name with the match in bold, the folder trail under it.
final class QuickSearchCell: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private let trail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        name.font = .systemFont(ofSize: 14)
        trail.font = .systemFont(ofSize: 11)
        trail.textColor = .secondaryLabelColor
        for label in [name, trail] {
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
        }
        name.topAnchor.constraint(equalTo: topAnchor, constant: 4).isActive = true
        trail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ result: QuickSearch.Result) {
        let text = NSMutableAttributedString(string: result.displayName)
        let chars = Array(result.displayName)
        for range in result.matched where range.upperBound <= chars.count {
            let start = String(chars[..<range.lowerBound]).utf16.count
            let length = String(chars[range]).utf16.count
            text.addAttributes([.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.controlAccentColor],
                               range: NSRange(location: start, length: length))
        }
        name.attributedStringValue = text
        trail.stringValue = result.candidate.breadcrumb
    }
}

extension EditorWindowController {
    /// Go > Quick Search (⇧⌘O): the panel over this window; a chosen file opens here, with the
    /// keyboard in the editor.
    @objc func showQuickSearch(_ sender: Any?) {
        guard let window else { return }
        QuickSearchController.shared.show(over: window) { [weak self] url in self?.fileList.onOpen?(url, true) }
    }
}
