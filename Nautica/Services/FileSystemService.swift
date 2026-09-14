import Foundation

/// File listing, metadata, and NSFileCoordinator wrappers.
actor FileSystemService {
    static let shared = FileSystemService()

    private static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isHiddenKey,
        .contentTypeKey,
    ]

    /// Enumerates a directory via NSFileCoordinator, returning sorted items.
    /// Unreadable directories propagate their error to the browser.
    func contentsOfDirectory(at url: URL, includingHidden: Bool) async throws -> [FileItem] {
        var items: [FileItem] = []
        var coordinationError: NSError?
        var enumerationError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let childURLs = try FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: includingHidden ? [] : [.skipsHiddenFiles]
                )
                items = childURLs.compactMap { makeItem(from: $0, includingHidden: includingHidden) }
            } catch {
                enumerationError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let enumerationError { throw enumerationError }

        return items.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Builds a FileItem for a single URL, or nil if unreadable.
    func attributesOfItem(at url: URL) -> FileItem? {
        makeItem(from: url, includingHidden: true)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Private

    private func makeItem(from url: URL, includingHidden: Bool) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else {
            return nil
        }
        let isHidden = values.isHidden ?? url.lastPathComponent.hasPrefix(".")
        if isHidden && !includingHidden { return nil }

        return FileItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: values.fileSize.map { Int64($0) },
            modificationDate: values.contentModificationDate,
            creationDate: values.creationDate,
            isHidden: isHidden,
            kind: values.contentType?.localizedDescription ?? ""
        )
    }
}
