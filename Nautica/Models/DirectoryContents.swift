import Foundation

/// Observable container for a directory listing.
@Observable
final class DirectoryContents {
    var url: URL
    var items: [FileItem] = []
    var isLoading: Bool = false
    var showHiddenFiles: Bool = false
    var error: Error?

    /// Active sort, shared by the icon and list views (folders always first).
    var sortKey: SortKey = .name
    var sortAscending: Bool = true

    init(url: URL) {
        self.url = url
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
                items = Self.sort(contents, by: sortKey, ascending: sortAscending)
            } catch {
                items = []
                self.error = error
            }
            isLoading = false
        }
    }

    /// Sorts the current items in place by the given key path.
    func sort(by keyPath: KeyPath<FileItem, some Comparable>) {
        items.sort { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// Changes the active sort and re-sorts the current items in place.
    /// Both file views observe `items`, so they share the resulting order.
    func sort(by key: SortKey, ascending: Bool) {
        sortKey = key
        sortAscending = ascending
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
