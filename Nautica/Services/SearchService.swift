import Foundation
import Combine

/// Scope for Spotlight searching.
enum SearchScope: Hashable {
    case localComputer
    case folder(URL)

    var displayName: String {
        switch self {
        case .localComputer:
            return "This Mac"
        case .folder(let url):
            return url.lastPathComponent.isEmpty ? "Current Folder" : url.lastPathComponent
        }
    }
}

/// Content filtering options for Spotlight queries.
enum SearchFilter: String, CaseIterable {
    case nameAndContent = "Name and Content"
    case nameOnly = "Name Matches"
}

/// Service managing Spotlight search queries via `NSMetadataQuery`.
/// Supports system-wide and folder-scoped searches, live result notifications,
/// and exporting searches as macOS `.savedSearch` property lists.
@MainActor
final class SearchService: ObservableObject {
    static let shared = SearchService()

    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isGathering: Bool = false
    @Published private(set) var searchScope: SearchScope = .localComputer
    @Published private(set) var searchFilter: SearchFilter = .nameAndContent
    @Published private(set) var currentQuery: String = ""
    @Published private(set) var currentCriteria: [SearchCriterion] = []
    @Published private(set) var results: [FileItem] = []
    @Published private(set) var totalResultCount: Int = 0
    @Published private(set) var isTruncated: Bool = false
    public static let maxResultCap: Int = 500

    private var metadataQuery: NSMetadataQuery?
    private var queryObserverTokens: [NSObjectProtocol] = []
    private var onUpdateHandler: (([FileItem]) -> Void)?
    private var includeHiddenFiles: Bool = false

    private init() {}

    /// Initiates or updates an ongoing Spotlight search.
    func performSearch(
        query: String,
        scope: SearchScope,
        filter: SearchFilter = .nameAndContent,
        criteria: [SearchCriterion] = [],
        includingHidden: Bool = false,
        onUpdate: @escaping ([FileItem]) -> Void
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !criteria.isEmpty else {
            stopSearch()
            onUpdate([])
            return
        }

        self.currentQuery = trimmed
        self.currentCriteria = criteria
        self.searchScope = scope
        self.searchFilter = filter
        self.includeHiddenFiles = includingHidden
        self.onUpdateHandler = onUpdate
        self.isSearching = true
        self.isGathering = true

        stopActiveQuery()

        let queryObj = NSMetadataQuery()
        self.metadataQuery = queryObj

        // 1. Build Predicates
        var subpredicates: [NSPredicate] = []

        if !trimmed.isEmpty {
            let formattedQuery = "*\(trimmed)*"
            let textPredicate: NSPredicate
            switch filter {
            case .nameOnly:
                textPredicate = NSPredicate(
                    format: "(%K LIKE[cd] %@) OR (%K LIKE[cd] %@)",
                    kMDItemDisplayName as String, formattedQuery,
                    kMDItemFSName as String, formattedQuery
                )
            case .nameAndContent:
                textPredicate = NSPredicate(
                    format: "(%K LIKE[cd] %@) OR (%K LIKE[cd] %@) OR (%K LIKE[cd] %@)",
                    kMDItemDisplayName as String, formattedQuery,
                    kMDItemFSName as String, formattedQuery,
                    kMDItemTextContent as String, formattedQuery
                )
            }
            subpredicates.append(textPredicate)
        }

        for criterion in criteria {
            subpredicates.append(criterion.toPredicate())
        }

        let compoundPredicate: NSPredicate
        if subpredicates.isEmpty {
            compoundPredicate = NSPredicate(value: true)
        } else if subpredicates.count == 1 {
            compoundPredicate = subpredicates[0]
        } else {
            compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
        queryObj.predicate = compoundPredicate

        // 2. Set Scopes
        switch scope {
        case .localComputer:
            queryObj.searchScopes = [NSMetadataQueryLocalComputerScope]
        case .folder(let folderURL):
            queryObj.searchScopes = [folderURL]
        }

        // 3. Register Notifications
        let center = NotificationCenter.default
        let tokenGathering = center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: queryObj,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isGathering = false
            self.harvestResults(from: queryObj)
        }

        let tokenUpdate = center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: queryObj,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.harvestResults(from: queryObj)
        }

        queryObserverTokens = [tokenGathering, tokenUpdate]

        // 4. Start search
        queryObj.start()
    }

    /// Terminates the current search and cleans up query resources.
    func stopSearch() {
        stopActiveQuery()
        isSearching = false
        isGathering = false
        currentQuery = ""
        currentCriteria = []
        results = []
        totalResultCount = 0
        isTruncated = false
        onUpdateHandler = nil
    }

    private func stopActiveQuery() {
        if let queryObj = metadataQuery {
            queryObj.disableUpdates()
            queryObj.stop()
            for token in queryObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
            queryObserverTokens.removeAll()
            metadataQuery = nil
        }
    }

    /// Converts query results into `[FileItem]` models.
    private func harvestResults(from queryObj: NSMetadataQuery) {
        queryObj.disableUpdates()
        defer { queryObj.enableUpdates() }

        let count = queryObj.resultCount
        self.totalResultCount = count
        self.isTruncated = count > Self.maxResultCap

        var items: [FileItem] = []
        items.reserveCapacity(min(count, Self.maxResultCap))

        for i in 0..<min(count, Self.maxResultCap) {
            guard let mdItem = queryObj.result(at: i) as? NSMetadataItem,
                  let path = mdItem.value(forAttribute: kMDItemPath as String) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)

            // If folder-scoped, ensure url is actually within target directory
            if case .folder(let folderURL) = searchScope {
                if !url.path.hasPrefix(folderURL.path) {
                    continue
                }
            }

            // Hidden file filter
            if !includeHiddenFiles && (url.lastPathComponent.hasPrefix(".") || (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true) {
                continue
            }

            if let item = makeFileItem(from: url) {
                items.append(item)
            }
        }

        self.results = items
        self.onUpdateHandler?(items)
    }

    private func makeFileItem(from url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: [
            .nameKey, .isDirectoryKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey,
            .isHiddenKey, .contentTypeKey, .tagNamesKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey, .ubiquitousItemHasUnresolvedConflictsKey
        ]) else { return nil }

        let provider = CloudStorageService.provider(for: url)
        let cloudStatus = CloudStorageService.cloudStatus(for: url, resourceValues: values)

        return FileItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: values.fileSize.map { Int64($0) },
            modificationDate: values.contentModificationDate,
            creationDate: values.creationDate,
            isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
            kind: values.contentType?.localizedDescription ?? "",
            cloudStatus: cloudStatus,
            cloudProvider: provider,
            tags: values.tagNames ?? []
        )
    }

    /// Exports the current query as a macOS `.savedSearch` plist file in `~/Library/Saved Searches/`.
    @discardableResult
    func saveSmartFolder(
        name: String,
        query: String,
        scope: SearchScope,
        criteria: [SearchCriterion] = []
    ) throws -> URL {
        let savedSearchesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Searches", isDirectory: true)
        if !FileManager.default.fileExists(atPath: savedSearchesDir.path) {
            try FileManager.default.createDirectory(at: savedSearchesDir, withIntermediateDirectories: true)
        }

        let fileName = name.hasSuffix(".savedSearch") ? name : "\(name).savedSearch"
        let fileURL = savedSearchesDir.appendingPathComponent(fileName)

        var queryParts: [String] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            queryParts.append("(kMDItemDisplayName == '*\(trimmed)*'cd || kMDItemTextContent == '*\(trimmed)*'cd)")
        }

        for criterion in criteria {
            let part = criterion.toRawQuery()
            if part != "true" {
                queryParts.append("(\(part))")
            }
        }

        var currentFolderPaths: [String] = []
        if case .folder(let url) = scope {
            currentFolderPaths.append(url.path)
            queryParts.append("(kMDItemPath == '\(url.path)/*'c)")
        }

        let rawQueryStr = queryParts.isEmpty ? "true" : queryParts.joined(separator: " && ")

        let plistDict: [String: Any] = [
            "CompatibleVersion": 1,
            "RawQuery": rawQueryStr,
            "SearchCriteria": [
                "CurrentFolderPath": currentFolderPaths
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try data.write(to: fileURL)
        return fileURL
    }
}
