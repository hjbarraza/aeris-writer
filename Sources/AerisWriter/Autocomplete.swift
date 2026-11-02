import AppKit
import MarkdownCore

/// What the autocomplete popup offers from a document's own folder: its Markdown
/// notes (for `[[`), its entries (for `](`), and each note's `#tags`. One level only.
struct FolderSnapshot: Sendable {
    let date: Date
    /// File name → tags, for Markdown files (the document's own file is left out by the caller).
    let tagsByFile: [String: [String]]
    /// Markdown file names without extension.
    let notes: [String]
    /// Entry names; folders end in `/`.
    let entries: [String]
}

/// Folder scans, cached per folder for a few seconds and read off the main thread.
/// Never reads outside the folder: no recursion, symlinks are listed but not read.
@MainActor final class FolderIndex {
    static let shared = FolderIndex()
    static let ttl: TimeInterval = 10
    nonisolated static let maxFiles = 500, maxFileSize = 1_000_000

    private var cache: [URL: FolderSnapshot] = [:]
    private var scanning: Set<URL> = []

    /// The cached snapshot, possibly stale or nil. A missing or stale one starts a
    /// background scan; `updated` runs on the main thread when it lands.
    func snapshot(for folder: URL, updated: @escaping @MainActor () -> Void) -> FolderSnapshot? {
        let cached = cache[folder]
        if cached.map({ Date().timeIntervalSince($0.date) > Self.ttl }) ?? true, scanning.insert(folder).inserted {
            Task {
                let snap = await Task.detached(priority: .userInitiated) { Self.scan(folder) }.value
                self.cache[folder] = snap
                self.scanning.remove(folder)
                updated()
            }
        }
        return cached
    }

    nonisolated static func scan(_ folder: URL) -> FolderSnapshot {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(maxFiles)
        var tags: [String: [String]] = [:], notes: [String] = [], entries: [String] = []
        for url in urls {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            entries.append(v?.isDirectory == true ? name + "/" : name)
            guard ["md", "markdown"].contains(url.pathExtension.lowercased()), v?.isDirectory != true else { continue }
            notes.append(url.deletingPathExtension().lastPathComponent)
            guard v?.isSymbolicLink != true, v?.isRegularFile == true, (v?.fileSize ?? .max) <= maxFileSize,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            tags[name] = Hashtags.extract(text)
        }
        return FolderSnapshot(date: Date(), tagsByFile: tags, notes: notes, entries: entries)
    }
}

/// The completion list: a borderless child window under the caret with a one-column
/// table. It never becomes key; the editor drives it from its key commands.
@MainActor final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var items: [String] = []
    var onAccept: (() -> Void)?
    private let table = NSTableView()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        p.contentView = scroll
        return p
    }()

    static let rowHeight: CGFloat = 20, maxRows = 8, width: CGFloat = 240

    var isVisible: Bool { panel.isVisible }
    var selected: String? { items.indices.contains(table.selectedRow) ? items[table.selectedRow] : nil }

    /// Shows `items` (first one selected) with the popup's top-left at `caret`'s
    /// bottom-left (`caret` in screen coordinates), as a child of `window`.
    func show(_ items: [String], below caret: NSRect, in window: NSWindow) {
        self.items = items
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let height = CGFloat(min(items.count, Self.maxRows)) * Self.rowHeight
        panel.setFrame(NSRect(x: caret.minX, y: caret.minY - height - 2, width: Self.width, height: height), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Moves the selection by `delta` rows, clamped to the list.
    func move(_ delta: Int) {
        let row = min(max(table.selectedRow + delta, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func clicked() {
        if table.clickedRow >= 0 { onAccept?() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: items[row])
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
