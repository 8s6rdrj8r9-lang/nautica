import Foundation

/// Persistent store tracking original locations of trashed files so they can
/// be restored to their pre-trash directories using Finder-style "Put Back" (⌘⌫).
final class TrashOriginStore {
    static let shared = TrashOriginStore()

    private let storeURL: URL
    private var mappings: [String: String] = [:] // [trashedPath: originalPath]
    private let queue = DispatchQueue(label: "com.nautica.TrashOriginStore", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nautica", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        self.storeURL = appSupport.appendingPathComponent("trash_origins.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        self.mappings = dict
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    /// Records a list of trashed transfers.
    func record(transfers: [FileOperationResult.Transfer]) {
        queue.sync {
            for transfer in transfers {
                mappings[transfer.destination.path] = transfer.original.path
            }
            save()
        }
    }

    /// Returns whether the given URL was deleted and can be put back.
    func canPutBack(url: URL) -> Bool {
        queue.sync {
            mappings[url.path] != nil || isInsideTrash(url)
        }
    }

    /// Returns the recorded original pre-trash URL, if known.
    func originalURL(for trashedURL: URL) -> URL? {
        queue.sync {
            if let path = mappings[trashedURL.path] {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
    }

    /// Checks whether a URL is located in the user's Trash.
    func isInsideTrash(_ url: URL) -> Bool {
        url.path.contains("/.Trash") || url.path.hasSuffix("/.Trash")
    }

    /// Restores items to their recorded pre-trash original paths.
    func putBack(urls: [URL]) async -> FileOperationResult {
        var result = FileOperationResult()
        for trashedURL in urls {
            let original: URL
            if let stored = originalURL(for: trashedURL) {
                original = stored
            } else {
                // Fallback: restore to Desktop if origin metadata was not captured
                original = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                    .appendingPathComponent(trashedURL.lastPathComponent)
            }

            // Ensure destination directory exists
            let parentDir = original.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Unique destination if colliding
            var target = original
            var counter = 2
            let nameWithoutExt = original.deletingPathExtension().lastPathComponent
            let ext = original.pathExtension
            while FileManager.default.fileExists(atPath: target.path) {
                let newName = ext.isEmpty ? "\(nameWithoutExt) \(counter)" : "\(nameWithoutExt) \(counter).\(ext)"
                target = parentDir.appendingPathComponent(newName)
                counter += 1
            }

            do {
                try FileManager.default.moveItem(at: trashedURL, to: target)
                result.transfers.append(.init(original: trashedURL, destination: target))
                queue.sync {
                    self.mappings.removeValue(forKey: trashedURL.path)
                    self.save()
                }
            } catch {
                result.failed.append((trashedURL, error))
            }
        }
        return result
    }
}
