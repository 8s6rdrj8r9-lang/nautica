import Foundation

/// Observable container for a directory listing.
@Observable
final class DirectoryContents {
    var url: URL {
        didSet {
            if oldValue != url {
                startWatcher()
            }
        }
    }
    var rawItems: [FileItem] = []
    var items: [FileItem] = []
    var isLoading: Bool = false
    var showHiddenFiles: Bool = false
    var error: Error?

    var filterText: String = "" {
        didSet {
            if oldValue != filterText { applyFilter() }
        }
    }
    var filterTag: TagColor? = nil {
        didSet {
            if oldValue != filterTag { applyFilter() }
        }
    }

    var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty || filterTag != nil
    }

    var totalUnfilteredCount: Int {
        rawItems.count
    }

    func clearFilter() {
        filterText = ""
        filterTag = nil
    }

    private func applyFilter() {
        var result = rawItems
        let query = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.name.lowercased().contains(query)
            }
        }
        if let filterTag {
            result = result.filter { item in
                item.tagColors.contains(filterTag)
            }
        }
        items = Self.sort(result, by: sortKey, ascending: sortAscending)
    }

    @ObservationIgnored
    private var watcher: DirectoryWatcherService?

    /// Active sort, shared by the icon and list views (folders always first).
    var sortKey: SortKey = .name
    var sortAscending: Bool = true
    /// Active group criterion (Finder "Use Groups" / "Arrange By").
    var groupBy: GroupByCriterion = .none {
        didSet {
            if oldValue != groupBy {
                onGroupingChanged?()
            }
        }
    }
    var onGroupingChanged: (() -> Void)?

    /// Classified groups based on current items and groupBy criterion.
    func groupedSections() -> [FileItemGroup] {
        GroupClassifier.classify(items, by: groupBy)
    }

    init(url: URL) {
        self.url = url
        startWatcher()
    }

    private func startWatcher() {
        watcher?.stopWatching()
        watcher = DirectoryWatcherService(url: url) { [weak self] in
            self?.reload()
        }
    }

    /// Re-enumerates the directory on a background actor and applies
    /// the hidden-file filter and the active sort (`sortKey`/`sortAscending`).
    func reload() {
        isLoading = true
        error = nil
        let url = self.url
        let includeHidden = showHiddenFiles
        Task {
            do {
                let contents = try await FileSystemService.shared
                    .contentsOfDirectory(at: url, includingHidden: includeHidden)
                rawItems = contents
                applyFilter()
            } catch {
                rawItems = []
                items = []
                self.error = error
            }
            isLoading = false
        }
    }

    /// Sorts the current items in place by the given key path.
    func sort(by keyPath: KeyPath<FileItem, some Comparable>) {
        rawItems.sort { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
        items.sort { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// Changes the active sort and re-sorts the current items in place.
    /// Both file views observe `items`, so they share the resulting order.
    func sort(by key: SortKey, ascending: Bool) {
        sortKey = key
        sortAscending = ascending
        rawItems = Self.sort(rawItems, by: key, ascending: ascending)
        items = Self.sort(items, by: key, ascending: ascending)
        onSortChanged?()
    }

    /// Called after the active sort changes (Prompt 12 persistence hook).
    var onSortChanged: (() -> Void)?

    /// Folders first, then by `key`; equal values fall back to name so the
    /// order stays stable. Names compare case-insensitively, Finder-style.
    static func sort(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            var result = compare(lhs, rhs, by: key)
            if result == .orderedSame {
                result = lhs.name.localizedStandardCompare(rhs.name)
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare(_ lhs: FileItem, _ rhs: FileItem, by key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return compareOptionals(lhs.size, rhs.size)
        case .modificationDate:
            return compareOptionals(lhs.modificationDate, rhs.modificationDate)
        case .creationDate:
            return compareOptionals(lhs.creationDate, rhs.creationDate)
        case .kind:
            return lhs.kind.localizedCaseInsensitiveCompare(rhs.kind)
        }
    }

    /// Missing values sort after present ones regardless of direction.
    private static func compareOptionals<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }

    /// Default ordering: folders first, then name A→Z, case-insensitive.
    static func sort(_ items: [FileItem]) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
