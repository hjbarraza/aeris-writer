import AppKit
import LibraryCore
import MarkdownCore

/// The floating panel behind Go > Quick Search (⇧⌘O). Typing ranks the files of every location by
/// name; Return opens the selected one in the window it was opened from, Esc gives the keyboard
/// back to where it was. Names are enumerated off the main thread when the panel opens (no index),
/// and any new input cancels the ranking still running for the old one. Under the file names come
/// two groups found by reading the files (M2-23): matches in the open document, then matches in the
/// other files (headings and text). The reading is on a background queue, capped, and cancelled by
/// the next keystroke; it never writes.
@MainActor
final class QuickSearchController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickSearchController()

    private static let width: CGFloat = 560, fieldHeight: CGFloat = 52, maxListHeight: CGFloat = 400
    /// Matches listed per group before "N more", and files listed under "Other files".
    private static let shownInThisFile = 5, shownPerFile = 3
    private nonisolated static let maxFiles = 20

    /// Where the caret goes in a file the panel opens.
    enum Landing { case none, start, end, range(NSRange) }

    /// What the panel lists, top to bottom.
    private enum Row {
        case section(String)
        case name(QuickSearch.Result)
        case thisMatch(QuickSearch.ContentMatch)
        case thisMore(Int)
        case findReplace
        case fileHeader(QuickSearch.Candidate)
        case match(QuickSearch.Candidate, QuickSearch.ContentMatch)
        case fileMore(QuickSearch.Candidate, Int, QuickSearch.ContentMatch)

        var isSelectable: Bool { if case .section = self { false } else { true } }
        var height: CGFloat {
            switch self {
            case .section: 24
            case .name: 40
            case .fileHeader: 36
            default: 26
            }
        }
        var id: String {
            switch self {
            case .section(let t): "section:\(t)"
            case .name(let r): "name:\(r.candidate.path)"
            case .thisMatch(let m): "this:\(m.range.location)"
            case .thisMore: "thisMore"
            case .findReplace: "findReplace"
            case .fileHeader(let c): "header:\(c.path)"
            case .match(let c, let m): "match:\(c.path):\(m.range.location)"
            case .fileMore(let c, _, _): "fileMore:\(c.path)"
            }
        }
        /// A plain-text account of the row, for the self-check.
        var summary: String {
            switch self {
            case .section(let t): "section: \(t)"
            case .name(let r): "file: \(r.candidate.fileName)"
            case .thisMatch(let m): "this \(m.kind.label): \(m.snippet)"
            case .thisMore(let n): "this more: \(n)"
            case .findReplace: "find and replace"
            case .fileHeader(let c): "header: \(c.fileName)"
            case .match(let c, let m): "\(m.kind.label) in \(c.fileName): \(m.snippet)"
            case .fileMore(let c, let n, _): "more in \(c.fileName): \(n)"
            }
        }
    }

    /// Built once and reused; `panel` is it only while it is on screen.
    private var window: QuickSearchPanel?
    private var onScreen = false
    var panel: QuickSearchPanel? { onScreen ? window : nil }
    /// The files whose names match.
    private(set) var results: [QuickSearch.Result] = []
    private var rows: [Row] = []
    private var thisFile: [QuickSearch.ContentMatch] = []
    private var fileHits: [QuickSearch.FileHits] = []
    private var contentFlag: QuickSearch.CancelFlag?
    private var contentRun = 0
    /// What the background reading is looking for, fixed per keystroke.
    private var contentJob: (query: String, headings: Bool, text: Bool, skip: String?)?
    private var currentDocument: (() -> (url: URL?, text: String)?)?
    private var selectInDocument: ((NSRange) -> Void)?
    private var findAndReplace: ((String) -> Void)?
    private let filterButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let field = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    private var candidates: [QuickSearch.Candidate] = []
    private var generation = 0
    private var enumeration: QuickSearch.CancelFlag?
    private var ranking: Task<Void, Never>?
    private weak var parent: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var openFile: ((URL, Landing) -> Void)?
    private var focusEditor: (() -> Void)?
    /// The query `results` were ranked for; a result list for any other text is never applied or opened.
    private var resultsQuery = ""
    /// Return was pressed before the ranking for the current text landed; it opens when it does.
    /// The text Return was pressed for while its ranking was still running (and which press it was).
    private var openWhenRanked: String?
    private var returnPress = 0
    /// Self-check hook: a delay before ranking a given query, to make rankings land out of order.
    var rankDelayForTesting: ((String) -> TimeInterval)?

    private static let enumerationQueue = DispatchQueue(label: "aeris.quicksearch.enumerate", qos: .userInitiated)
    private static let contentQueue = DispatchQueue(label: "aeris.quicksearch.content", qos: .userInitiated)

    // MARK: Filters (kept across launches)

    static let textKey = "QuickSearch.includeText", headingsKey = "QuickSearch.includeHeadings"
    static var includesText: Bool {
        get { AppDefaults.store.object(forKey: textKey) as? Bool ?? true }
        set { AppDefaults.store.set(newValue, forKey: textKey) }
    }
    static var includesHeadings: Bool {
        get { AppDefaults.store.object(forKey: headingsKey) as? Bool ?? true }
        set { AppDefaults.store.set(newValue, forKey: headingsKey) }
    }

    /// Turns the text and heading results on or off, as the filter menu does.
    func setFilters(text: Bool, headings: Bool) {
        Self.includesText = text
        Self.includesHeadings = headings
        syncFilterMenu()
        rerank()
    }

    @objc private func toggleText(_ sender: Any?) { setFilters(text: !Self.includesText, headings: Self.includesHeadings) }
    @objc private func toggleHeadings(_ sender: Any?) { setFilters(text: Self.includesText, headings: !Self.includesHeadings) }

    private func syncFilterMenu() {
        filterButton.menu?.items[1].state = Self.includesText ? .on : .off
        filterButton.menu?.items[2].state = Self.includesHeadings ? .on : .off
    }

    /// The rows as plain text (self-check).
    var rowSummaries: [String] { rows.map(\.summary) }

    /// Selects the first row whose summary contains `text` (self-check).
    @discardableResult func selectRow(containing text: String) -> Bool {
        guard let i = rows.firstIndex(where: { $0.summary.contains(text) }), rows[i].isSelectable else { return false }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        return true
    }

    /// Opens a file at its start or end, as a header's Start and End do.
    func jump(toEndOf candidate: QuickSearch.Candidate, end: Bool) { open(candidate, landing: end ? .end : .start) }

    var isShown: Bool { panel != nil }
    var query: String { field.stringValue }

    // MARK: Showing and closing

    /// Opens the panel over `window` and starts listing the library. `open` receives the chosen file;
    /// `focusEditor` gives the keyboard back to the editor. A window that is not on screen shows nothing.
    func show(over window: NSWindow, focusEditor: @escaping () -> Void,
              currentDocument: @escaping () -> (url: URL?, text: String)?,
              select: @escaping (NSRange) -> Void, findAndReplace: @escaping (String) -> Void,
              open: @escaping (URL, Landing) -> Void) {
        guard window.isVisible else { return }
        if isShown { close(restoreFocus: false) }
        parent = window
        self.focusEditor = focusEditor
        self.currentDocument = currentDocument
        selectInDocument = select
        self.findAndReplace = findAndReplace
        openFile = open
        candidates = []
        results = []
        rows = []
        thisFile = []
        fileHits = []
        contentFlag?.cancel(); contentJob = nil
        resultsQuery = ""
        openWhenRanked = nil
        generation += 1
        let panel = self.window ?? QuickSearchPanel(controller: self)
        if self.window == nil { build(in: panel); self.window = panel }
        onScreen = true
        field.stringValue = ""
        syncFilterMenu()
        table.reloadData()
        layoutPanel()
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(restoreFocus: false) }
        }
        startEnumeration(roots: Library.shared.tree.roots.map(\.url))
    }

    /// Closes the panel. Esc and a chosen result put the keyboard in the editor.
    func close(restoreFocus: Bool = true) {
        guard let panel else { return }
        generation += 1
        enumeration?.cancel(); ranking?.cancel(); contentFlag?.cancel()
        openWhenRanked = nil
        onScreen = false
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoreFocus, let parent {
            parent.makeKeyAndOrderFront(nil)
            focusEditor?()
        }
    }

    /// Lists the library on a dedicated serial queue (not the cooperative pool), checking for
    /// cancellation between folders.
    private func startEnumeration(roots: [URL]) {
        let gen = generation, flag = QuickSearch.CancelFlag()
        enumeration = flag
        Self.enumerationQueue.async { [weak self] in
            QuickSearch.enumerate(roots: roots, isCancelled: { flag.isCancelled }) { batch in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.add(batch, generation: gen) }
                }
            }
        }
    }

    private func add(_ batch: [QuickSearch.Candidate], generation gen: Int) {
        guard gen == generation, isShown else { return }
        candidates += batch
        rerank(restartContent: false)
        scanContent(batch)
    }

    // MARK: Ranking

    /// Types `text` into the field, as the user would.
    func setQuery(_ text: String) {
        field.stringValue = text
        rerank()
    }

    func controlTextDidChange(_ obj: Notification) { rerank() }

    /// Ranks the names for the text in the field. A new text also restarts the reading of file contents;
    /// more files arriving (`restartContent: false`) only re-rank the names.
    private func rerank(restartContent: Bool = true) {
        ranking?.cancel()
        if restartContent { startContent() }
        if openWhenRanked != field.stringValue { openWhenRanked = nil }   // typing on cancels a pending Return
        let query = field.stringValue, snapshot = candidates, gen = generation
        let delay = rankDelayForTesting?(query) ?? 0
        let showExtension = AppDefaults.store.bool(forKey: FileListViewController.showExtensionsKey)
        ranking = Task.detached(priority: .userInitiated) { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            let ranked = QuickSearch.rank(query: query, candidates: snapshot, showExtension: showExtension)
            if Task.isCancelled { return }  // superseded by a newer ranking of the same text
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(ranked, query: query, generation: gen) }
            }
        }
    }

    /// Takes a ranking only if it is for the text in the field now (rankings can land out of order).
    /// The highlighted file stays highlighted while more of the library arrives; a new query starts at the top.
    private func apply(_ ranked: [QuickSearch.Result], query: String, generation gen: Int) {
        guard gen == generation, isShown, query == field.stringValue else { return }
        let sameQuery = query == resultsQuery
        results = ranked
        resultsQuery = query
        refreshRows(newQuery: !sameQuery)
        if let pending = openWhenRanked, pending == field.stringValue { openWhenRanked = nil; openSelected() }
    }

    // MARK: Contents

    /// Begins reading for the text in the field: the open document first, then the files as they
    /// are listed. Whatever was being read for older text is cancelled.
    private func startContent() {
        contentFlag?.cancel()
        contentRun += 1
        thisFile = []; fileHits = []
        contentJob = nil
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let headings = Self.includesHeadings, text = Self.includesText
        guard !query.isEmpty, headings || text else { return }
        let flag = QuickSearch.CancelFlag()
        contentFlag = flag
        let document = currentDocument?()
        let skip = document?.url.map { LibraryListing.canonicalPath($0) }
        contentJob = (query, headings, text, skip)
        let run = contentRun, gen = generation
        let snapshot = candidates
        Self.contentQueue.async { [weak self] in
            if let document {
                let found = QuickSearch.search(in: document.text, query: query, headings: headings, text: text, maxFound: 100)
                if flag.isCancelled { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.applyThisFile(found, run: run, generation: gen) }
                }
            }
            Self.read(snapshot, query: query, headings: headings, text: text, skip: skip,
                      flag: flag, controller: self, run: run, generation: gen)
        }
    }

    /// Reads files that arrived after the reading began.
    private func scanContent(_ batch: [QuickSearch.Candidate]) {
        guard let job = contentJob, let flag = contentFlag, !batch.isEmpty else { return }
        let run = contentRun, gen = generation
        Self.contentQueue.async { [weak self] in
            Self.read(batch, query: job.query, headings: job.headings, text: job.text, skip: job.skip,
                      flag: flag, controller: self, run: run, generation: gen)
        }
    }

    /// Runs on the content queue: files are read and searched there, each hit goes to the main thread.
    private nonisolated static func read(_ files: [QuickSearch.Candidate], query: String, headings: Bool, text: Bool,
                                         skip: String?, flag: QuickSearch.CancelFlag, controller: QuickSearchController?,
                                         run: Int, generation gen: Int) {
        QuickSearch.searchFiles(query: query, candidates: files, headings: headings, text: text, maxFiles: maxFiles,
            read: { cand in
                if let skip, LibraryListing.canonicalPath(URL(fileURLWithPath: cand.path)) == skip { return nil }
                return QuickSearch.readIfSmall(cand.path).flatMap { TextEncoding.decode($0)?.text }
            },
            isCancelled: { flag.isCancelled },
            deliver: { hits in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { controller?.applyHits(hits, run: run, generation: gen) }
                }
            })
    }

    private func applyThisFile(_ found: [QuickSearch.ContentMatch], run: Int, generation gen: Int) {
        guard gen == generation, isShown, run == contentRun else { return }
        thisFile = found
        refreshRows(newQuery: false)
    }

    private func applyHits(_ hits: QuickSearch.FileHits, run: Int, generation gen: Int) {
        guard gen == generation, isShown, run == contentRun, fileHits.count < Self.maxFiles else { return }
        fileHits.append(hits)
        if fileHits.count >= Self.maxFiles { contentFlag?.cancel() }
        refreshRows(newQuery: false)
    }

    /// Rebuilds the list from the three groups. A highlighted row stays highlighted while more arrives;
    /// a new query starts at the first row that can be chosen.
    private func refreshRows(newQuery: Bool) {
        let keep = !newQuery && table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow].id : nil
        var list: [Row] = []
        let hasContent = !thisFile.isEmpty || !fileHits.isEmpty
        if !results.isEmpty {
            if hasContent { list.append(.section("Files")) }
            list += results.map(Row.name)
        }
        if !thisFile.isEmpty {
            list.append(.section("This file"))
            list += thisFile.prefix(Self.shownInThisFile).map(Row.thisMatch)
            if thisFile.count > Self.shownInThisFile { list.append(.thisMore(thisFile.count - Self.shownInThisFile)) }
            list.append(.findReplace)
        }
        if !fileHits.isEmpty {
            list.append(.section("Other files"))
            for hits in fileHits {
                list.append(.fileHeader(hits.candidate))
                list += hits.matches.prefix(Self.shownPerFile).map { Row.match(hits.candidate, $0) }
                if hits.matches.count > Self.shownPerFile {
                    list.append(.fileMore(hits.candidate, hits.matches.count - Self.shownPerFile, hits.matches[Self.shownPerFile]))
                }
            }
        }
        rows = list
        table.reloadData()
        if let row = keep.flatMap({ id in list.firstIndex { $0.id == id } }) ?? list.firstIndex(where: \.isSelectable) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        layoutPanel()
    }

    // MARK: Choosing

    /// Does what the selected row stands for (the first row if none is selected) and closes the panel.
    /// Results ranked for older text are never used: if the ranking for the current text is still
    /// running, this waits for it (for at most a second).
    func openSelected() {
        guard resultsQuery == field.stringValue else {
            guard !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            openWhenRanked = field.stringValue
            returnPress += 1
            let press = returnPress
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { if self?.returnPress == press { self?.openWhenRanked = nil } }
            }
            return
        }
        guard let row = table.selectedRow >= 0 ? table.selectedRow : rows.firstIndex(where: \.isSelectable),
              rows.indices.contains(row), rows[row].isSelectable else { return }
        switch rows[row] {
        case .section: return
        case .name(let r): open(r.candidate, landing: .none)
        case .fileHeader(let c): open(c, landing: .start)
        case .match(let c, let m), .fileMore(let c, _, let m): open(c, landing: .range(m.range))
        case .thisMatch(let m):
            let select = selectInDocument
            close()
            select?(m.range)
        case .thisMore, .findReplace:
            let find = findAndReplace, text = field.stringValue.trimmingCharacters(in: .whitespaces)
            close()
            find?(text)
        }
    }

    private func open(_ candidate: QuickSearch.Candidate, landing: Landing) {
        let open = openFile, url = URL(fileURLWithPath: candidate.path)
        close()
        open?(url, landing)
    }

    func moveSelection(by delta: Int) {
        var row = table.selectedRow
        repeat { row += delta } while rows.indices.contains(row) && !rows[row].isSelectable
        guard rows.indices.contains(row) else { return }
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
        guard table.clickedRow >= 0, rows.indices.contains(table.clickedRow), rows[table.clickedRow].isSelectable else { return }
        table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
        openSelected()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row].height }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].isSelectable }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        func cell<T: NSTableCellView>(_ id: String, _ make: () -> T) -> T {
            let identifier = NSUserInterfaceItemIdentifier(id)
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? T ?? make()
            cell.identifier = identifier
            return cell
        }
        switch rows[row] {
        case .name(let r):
            let c = cell("name") { QuickSearchCell() }
            c.show(r)
            return c
        case .section(let title):
            let c = cell("section") { QuickSearchLineCell(style: .section) }
            c.show(title)
            return c
        case .thisMatch(let m), .match(_, let m):
            let c = cell("match") { QuickSearchLineCell(style: .match) }
            c.show(m)
            return c
        case .thisMore(let n), .fileMore(_, let n, _):
            let c = cell("action") { QuickSearchLineCell(style: .action) }
            c.show("\(n) more")
            return c
        case .findReplace:
            let c = cell("action") { QuickSearchLineCell(style: .action) }
            c.show("Find and Replace\u{2026}")
            return c
        case .fileHeader(let cand):
            let c = cell("header") { QuickSearchHeaderCell() }
            c.show(cand) { [weak self] end in self?.jump(toEndOf: cand, end: end) }
            return c
        }
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

        filterButton.isBordered = false
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.addItem(withTitle: "")
        filterButton.item(at: 0)?.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle",
                                                  accessibilityDescription: "Filter results")
        filterButton.menu?.addItem(withTitle: "Text Results", action: #selector(toggleText(_:)), keyEquivalent: "").target = self
        filterButton.menu?.addItem(withTitle: "Heading Results", action: #selector(toggleHeadings(_:)), keyEquivalent: "").target = self
        filterButton.setAccessibilityLabel("Filter results")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        table.headerView = nil
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

        for v in [field, filterButton, rule, scroll] as [NSView] { background.addSubview(v) }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: filterButton.leadingAnchor, constant: -4),
            filterButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            filterButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 36),
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
        let list = min(rows.reduce(0) { $0 + $1.height }, Self.maxListHeight)
        let height = Self.fieldHeight + (rows.isEmpty ? 0 : list + 4)
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

private extension QuickSearch.ContentMatch.Kind {
    var label: String { if case .heading(let level) = self { "heading \(level)" } else { "text" } }
}

/// The match shown in bold and accent colour.
private func highlighted(_ text: String, _ range: Range<Int>?, size: CGFloat) -> NSAttributedString {
    let out = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
    let chars = Array(text)
    if let range, range.upperBound <= chars.count {
        let start = String(chars[..<range.lowerBound]).utf16.count
        out.addAttributes([.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.controlAccentColor],
                          range: NSRange(location: start, length: String(chars[range]).utf16.count))
    }
    return out
}

/// A one-line row: a group title, a match (with an `H2` badge for a heading), or an action.
final class QuickSearchLineCell: NSTableCellView {
    enum Style { case section, match, action }
    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")

    init(style: Style) {
        super.init(frame: .zero)
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        for v in [badge, label] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            v.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style == .section ? 14 : 26).isActive = true
        label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: style == .match ? 6 : 0).isActive = true
        label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        switch style {
        case .section:
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
        case .action:
            label.font = .systemFont(ofSize: 12)
            label.textColor = .controlAccentColor
        case .match:
            label.font = .systemFont(ofSize: 12)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ text: String) {
        badge.stringValue = ""
        label.stringValue = text
    }

    func show(_ match: QuickSearch.ContentMatch) {
        if case .heading(let level) = match.kind { badge.stringValue = "H\(level)" } else { badge.stringValue = "" }
        label.attributedStringValue = highlighted(match.snippet, match.highlight, size: 12)
    }
}

/// A file with matches under "Other files": its name and folder, and Start and End to open it at either end.
final class QuickSearchHeaderCell: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private let trail = NSTextField(labelWithString: "")
    private let start = NSButton(title: "Start", target: nil, action: nil)
    private let end = NSButton(title: "End", target: nil, action: nil)
    private var jump: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        trail.font = .systemFont(ofSize: 10)
        trail.textColor = .secondaryLabelColor
        for label in [name, trail] {
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true
        }
        for (button, selector) in [(start, #selector(jumpToStart)), (end, #selector(jumpToEnd))] {
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .controlAccentColor
            button.target = self
            button.action = selector
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        end.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12).isActive = true
        start.trailingAnchor.constraint(equalTo: end.leadingAnchor, constant: -4).isActive = true
        name.trailingAnchor.constraint(lessThanOrEqualTo: start.leadingAnchor, constant: -8).isActive = true
        trail.trailingAnchor.constraint(lessThanOrEqualTo: start.leadingAnchor, constant: -8).isActive = true
        name.topAnchor.constraint(equalTo: topAnchor, constant: 3).isActive = true
        trail.topAnchor.constraint(equalTo: name.bottomAnchor).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ candidate: QuickSearch.Candidate, jump: @escaping (Bool) -> Void) {
        name.stringValue = candidate.fileName
        trail.stringValue = candidate.breadcrumb
        self.jump = jump
    }

    @objc private func jumpToStart() { jump?(false) }
    @objc private func jumpToEnd() { jump?(true) }
}

extension EditorWindowController {
    /// Go > Quick Search (⇧⌘O): the panel over this window; a chosen file opens here, with the
    /// keyboard in the editor and the caret where the result was.
    @objc func showQuickSearch(_ sender: Any?) {
        guard let window else { return }
        QuickSearchController.shared.show(
            over: window, focusEditor: { [weak self] in self?.focusEditor() },
            currentDocument: { [weak self] in
                (self?.document as? MarkdownDocument).map { ($0.fileURL, $0.textStorage.string) }
            },
            select: { [weak self] range in self?.focusEditor(); self?.selectInEditor(range) },
            findAndReplace: { [weak self] query in self?.showFindAndReplace(query: query) },
            open: { [weak self] url, landing in
                self?.openFile(url, focusEditor: true) {
                    switch landing {
                    case .none: break
                    case .start: self?.selectInEditor(NSRange(location: 0, length: 0))
                    case .end: self?.selectInEditor(NSRange(location: .max, length: 0))
                    case .range(let range): self?.selectInEditor(range)
                    }
                }
            })
    }
}
