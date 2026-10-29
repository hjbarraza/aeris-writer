import Foundation

public enum SortKey: String, CaseIterable, Sendable {
    case dateModified, dateCreated, name, fileExtension
    public var isDate: Bool { self == .dateModified || self == .dateCreated }
}

public enum DateShown: String, CaseIterable, Sendable { case modified, created, none }

public enum ListNavigation: String, CaseIterable, Sendable {
    /// Folders expand inline in the list.
    case tree
    /// Opening a folder replaces the list with its contents.
    case list
}

/// How the file list is sorted and drawn. Global for folder views; persisted in `UserDefaults`.
public struct FileListOptions: Equatable, Sendable {
    public var sortKey: SortKey = .dateModified
    /// False is the natural first order for the key: Newest First for dates, A to Z for name and extension.
    public var reversed = false
    public var foldersOnTop = false
    public var showDate: DateShown = .modified
    public var showExcerpts = true
    public var navigation: ListNavigation = .tree
    public var showSortBar = true

    public init() {}

    public init(sortKey: SortKey, reversed: Bool, foldersOnTop: Bool, showDate: DateShown,
                showExcerpts: Bool, navigation: ListNavigation, showSortBar: Bool) {
        self.sortKey = sortKey; self.reversed = reversed; self.foldersOnTop = foldersOnTop
        self.showDate = showDate; self.showExcerpts = showExcerpts
        self.navigation = navigation; self.showSortBar = showSortBar
    }

    /// How the direction reads for the current key.
    public var directionTitle: String { Self.directionTitle(key: sortKey, reversed: reversed) }

    public static func directionTitle(key: SortKey, reversed: Bool) -> String {
        key.isDate ? (reversed ? "Oldest First" : "Newest First") : (reversed ? "Z → A" : "A → Z")
    }

    public var sortTitle: String {
        switch sortKey {
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .name: "Name"
        case .fileExtension: "Extension"
        }
    }

    private enum Key {
        static let sortKey = "FileList.sortKey", reversed = "FileList.reversed", foldersOnTop = "FileList.foldersOnTop"
        static let showDate = "FileList.showDate", showExcerpts = "FileList.showExcerpts"
        static let navigation = "FileList.navigation", showSortBar = "FileList.showSortBar"
    }

    /// The stored options; anything missing or unreadable is the default.
    public static func load(from defaults: UserDefaults) -> FileListOptions {
        var o = FileListOptions()
        o.sortKey = defaults.string(forKey: Key.sortKey).flatMap(SortKey.init) ?? o.sortKey
        o.showDate = defaults.string(forKey: Key.showDate).flatMap(DateShown.init) ?? o.showDate
        o.navigation = defaults.string(forKey: Key.navigation).flatMap(ListNavigation.init) ?? o.navigation
        o.reversed = defaults.object(forKey: Key.reversed) as? Bool ?? o.reversed
        o.foldersOnTop = defaults.object(forKey: Key.foldersOnTop) as? Bool ?? o.foldersOnTop
        o.showExcerpts = defaults.object(forKey: Key.showExcerpts) as? Bool ?? o.showExcerpts
        o.showSortBar = defaults.object(forKey: Key.showSortBar) as? Bool ?? o.showSortBar
        return o
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(sortKey.rawValue, forKey: Key.sortKey)
        defaults.set(reversed, forKey: Key.reversed)
        defaults.set(foldersOnTop, forKey: Key.foldersOnTop)
        defaults.set(showDate.rawValue, forKey: Key.showDate)
        defaults.set(showExcerpts, forKey: Key.showExcerpts)
        defaults.set(navigation.rawValue, forKey: Key.navigation)
        defaults.set(showSortBar, forKey: Key.showSortBar)
    }
}

/// The order of one folder's rows.
public enum FileListSort {
    /// What the order looks at.
    public struct Item: Sendable {
        public let name: String
        public let isDirectory: Bool
        public let modified: Date?
        public let created: Date?
        public init(name: String, isDirectory: Bool, modified: Date?, created: Date?) {
            self.name = name; self.isDirectory = isDirectory; self.modified = modified; self.created = created
        }
    }

    /// Ordered by the key (ties by name, A to Z); `reversed` flips only the key; folders first if asked.
    public static func sorted<T>(_ values: [T], options: FileListOptions, item: (T) -> Item) -> [T] {
        values.map { ($0, item($0)) }.sorted { a, b in
            if options.foldersOnTop, a.1.isDirectory != b.1.isDirectory { return a.1.isDirectory }
            let c = compare(a.1, b.1, key: options.sortKey)
            if c != 0 { return options.reversed ? c > 0 : c < 0 }
            return byName(a.1, b.1) < 0
        }.map(\.0)
    }

    /// Convenience for plain items.
    public static func sorted(_ items: [Item], options: FileListOptions) -> [Item] {
        sorted(items, options: options, item: { $0 })
    }

    /// Negative when `a` comes first in the key's natural order (newest first for dates, A to Z otherwise).
    private static func compare(_ a: Item, _ b: Item, key: SortKey) -> Int {
        switch key {
        case .dateModified: return newestFirst(a.modified, b.modified)
        case .dateCreated: return newestFirst(a.created, b.created)
        case .name: return byName(a, b)
        case .fileExtension:
            return rank((a.isDirectory ? "" : (a.name as NSString).pathExtension).lowercased()
                .localizedStandardCompare((b.isDirectory ? "" : (b.name as NSString).pathExtension).lowercased()))
        }
    }

    private static func newestFirst(_ a: Date?, _ b: Date?) -> Int {
        let x = a ?? .distantPast, y = b ?? .distantPast
        return x == y ? 0 : (x > y ? -1 : 1)
    }

    private static func byName(_ a: Item, _ b: Item) -> Int {
        a.name == b.name ? 0 : (LibraryListing.precedes(LibraryEntry(name: a.name, isDirectory: a.isDirectory),
                                                        LibraryEntry(name: b.name, isDirectory: b.isDirectory)) ? -1 : 1)
    }

    private static func rank(_ r: ComparisonResult) -> Int {
        r == .orderedAscending ? -1 : (r == .orderedDescending ? 1 : 0)
    }
}
