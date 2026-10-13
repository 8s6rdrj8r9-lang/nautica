import Foundation

/// Synchronization mode determining how differences between two folders are resolved.
enum SyncMode: String, CaseIterable, Identifiable, Sendable {
    case mirror = "mirror"
    case update = "update"
    case twoWay = "twoWay"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mirror: return "Mirror (Left → Right)"
        case .update: return "Update (Left → Right)"
        case .twoWay: return "Two-Way Sync"
        }
    }

    var summary: String {
        switch self {
        case .mirror:
            return "Makes the Right folder an exact clone of the Left folder. Newer/new files are copied; files in Right that are absent in Left are deleted."
        case .update:
            return "Copies new and newer files from Left to Right. Preserves any additional files existing in the Right folder without deleting."
        case .twoWay:
            return "Bi-directional synchronization. The newest version of each file is propagated in both directions, merging files from both folders."
        }
    }
}

/// Comparison classification between corresponding files or directories.
enum SyncDifferenceStatus: Sendable {
    case leftOnly
    case rightOnly
    case leftNewer
    case rightNewer
    case identical
    case conflict

    var label: String {
        switch self {
        case .leftOnly: return "Only in Left"
        case .rightOnly: return "Only in Right"
        case .leftNewer: return "Left Newer"
        case .rightNewer: return "Right Newer"
        case .identical: return "Identical"
        case .conflict: return "Conflict"
        }
    }
}

/// Planned action for a synchronized item.
enum SyncAction: String, CaseIterable, Identifiable, Sendable {
    case copyToRight = "copyToRight"
    case copyToLeft = "copyToLeft"
    case deleteRight = "deleteRight"
    case deleteLeft = "deleteLeft"
    case skip = "skip"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .copyToRight: return "arrow.right"
        case .copyToLeft: return "arrow.left"
        case .deleteRight: return "trash"
        case .deleteLeft: return "trash"
        case .skip: return "minus"
        }
    }

    var label: String {
        switch self {
        case .copyToRight: return "Copy → Right"
        case .copyToLeft: return "Copy ← Left"
        case .deleteRight: return "Delete Right"
        case .deleteLeft: return "Delete Left"
        case .skip: return "Skip"
        }
    }
}

/// A single detected file or folder difference between Left and Right directories.
struct SyncItemDifference: Identifiable, Sendable {
    let id = UUID()
    let relativePath: String
    let isDirectory: Bool
    let status: SyncDifferenceStatus
    var action: SyncAction
    let leftURL: URL?
    let rightURL: URL?
    let leftSize: Int64?
    let rightSize: Int64?
    let leftModDate: Date?
    let rightModDate: Date?
}

/// Service that analyzes directory hierarchies, calculates sync diffs, and executes synchronization.
final class FolderSyncService: @unchecked Sendable {
    static let shared = FolderSyncService()

    private init() {}

    /// Scans both directories, compares their contents recursively, and returns the difference list with default actions.
    func compareFolders(
        leftURL: URL,
        rightURL: URL,
        mode: SyncMode
    ) async throws -> [SyncItemDifference] {
        let fm = FileManager.default

        // Validate both roots exist and are directories
        var isLeftDir: ObjCBool = false
        guard fm.fileExists(atPath: leftURL.path, isDirectory: &isLeftDir), isLeftDir.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: leftURL.path])
        }
        var isRightDir: ObjCBool = false
        guard fm.fileExists(atPath: rightURL.path, isDirectory: &isRightDir), isRightDir.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: rightURL.path])
        }

        var leftFiles: [String: (url: URL, isDir: Bool, size: Int64, date: Date)] = [:]
        var rightFiles: [String: (url: URL, isDir: Bool, size: Int64, date: Date)] = [:]

        // Enumerate Left
        if let enumerator = fm.enumerator(
            at: leftURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let relPath = fileURL.path.replacingOccurrences(of: leftURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relPath.isEmpty {
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                    let isDir = values?.isDirectory ?? false
                    let size = Int64(values?.fileSize ?? 0)
                    let date = values?.contentModificationDate ?? Date.distantPast
                    leftFiles[relPath] = (fileURL, isDir, size, date)
                }
            }
        }

        // Enumerate Right
        if let enumerator = fm.enumerator(
            at: rightURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let relPath = fileURL.path.replacingOccurrences(of: rightURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relPath.isEmpty {
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                    let isDir = values?.isDirectory ?? false
                    let size = Int64(values?.fileSize ?? 0)
                    let date = values?.contentModificationDate ?? Date.distantPast
                    rightFiles[relPath] = (fileURL, isDir, size, date)
                }
            }
        }

        var allRelPaths = Set(leftFiles.keys).union(Set(rightFiles.keys))
        var differences: [SyncItemDifference] = []

        for relPath in allRelPaths.sorted() {
            let left = leftFiles[relPath]
            let right = rightFiles[relPath]

            let isDir = left?.isDir ?? right?.isDir ?? false
            let status: SyncDifferenceStatus
            let defaultAction: SyncAction

            if let l = left, let r = right {
                if l.isDir != r.isDir {
                    status = .conflict
                    defaultAction = .skip
                } else if l.isDir {
                    status = .identical
                    defaultAction = .skip
                } else {
                    // Compare file sizes and timestamps
                    let sizeDiffers = l.size != r.size
                    let timeDelta = abs(l.date.timeIntervalSince(r.date))

                    if !sizeDiffers && timeDelta < 2.0 {
                        // For files under 10MB, verify byte equivalence
                        var sameBytes = true
                        if l.size < 10 * 1024 * 1024,
                           let lData = try? Data(contentsOf: l.url),
                           let rData = try? Data(contentsOf: r.url) {
                            sameBytes = (lData == rData)
                        }
                        if sameBytes {
                            status = .identical
                            defaultAction = .skip
                        } else {
                            status = .conflict
                            defaultAction = (mode == .mirror) ? .copyToRight : .skip
                        }
                    } else if l.date > r.date {
                        status = .leftNewer
                        defaultAction = .copyToRight
                    } else if r.date > l.date {
                        status = .rightNewer
                        switch mode {
                        case .mirror:
                            // In mirror mode, left is authoritative: copy Left -> Right
                            defaultAction = .copyToRight
                        case .update:
                            // In update mode, keep newer on right
                            defaultAction = .skip
                        case .twoWay:
                            // In two-way mode, newer propagates Left <- Right
                            defaultAction = .copyToLeft
                        }
                    } else {
                        status = .conflict
                        defaultAction = .copyToRight
                    }
                }
            } else if let l = left {
                status = .leftOnly
                defaultAction = .copyToRight
            } else {
                // rightOnly
                status = .rightOnly
                switch mode {
                case .mirror:
                    defaultAction = .deleteRight
                case .update:
                    defaultAction = .skip
                case .twoWay:
                    defaultAction = .copyToLeft
                }
            }

            differences.append(SyncItemDifference(
                relativePath: relPath,
                isDirectory: isDir,
                status: status,
                action: defaultAction,
                leftURL: left?.url,
                rightURL: right?.url,
                leftSize: left?.size,
                rightSize: right?.size,
                leftModDate: left?.date,
                rightModDate: right?.date
            ))
        }

        return differences
    }

    /// Executes the synchronized actions with live progress reporting.
    func executeSync(
        differences: [SyncItemDifference],
        leftBaseURL: URL,
        rightBaseURL: URL,
        onProgress: ((_ completed: Int, _ total: Int, _ currentItem: String) -> Void)? = nil
    ) async throws -> (copied: Int, deleted: Int) {
        let fm = FileManager.default

        // Revalidate roots before any destructive execution
        var isLeftDir: ObjCBool = false
        guard fm.fileExists(atPath: leftBaseURL.path, isDirectory: &isLeftDir), isLeftDir.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: leftBaseURL.path])
        }
        var isRightDir: ObjCBool = false
        guard fm.fileExists(atPath: rightBaseURL.path, isDirectory: &isRightDir), isRightDir.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: rightBaseURL.path])
        }

        var copiedCount = 0
        var deletedCount = 0

        let actionable = differences.filter { $0.action != .skip }
        let total = actionable.count

        for (index, item) in actionable.enumerated() {
            try Task.checkCancellation()
            onProgress?(index + 1, total, item.relativePath)

            let targetLeft = leftBaseURL.appendingPathComponent(item.relativePath)
            let targetRight = rightBaseURL.appendingPathComponent(item.relativePath)

            switch item.action {
            case .copyToRight:
                guard let source = (item.leftURL != nil && fm.fileExists(atPath: item.leftURL!.path)) ? item.leftURL! : (fm.fileExists(atPath: targetLeft.path) ? targetLeft : nil) else {
                    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: targetLeft.path])
                }
                let parent = targetRight.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                // Stage the copy to protect existing destination
                let stagingURL = parent.appendingPathComponent(".nautica-sync-" + UUID().uuidString)
                try fm.copyItem(at: source, to: stagingURL)
                defer { try? fm.removeItem(at: stagingURL) }
                let exists = (try? fm.attributesOfItem(atPath: targetRight.path)) != nil
                let flags: UInt32 = exists ? 0 : UInt32(RENAME_EXCL)
                guard renamex_np(stagingURL.path, targetRight.path, flags) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: targetRight.path])
                }
                copiedCount += 1

            case .copyToLeft:
                guard let source = (item.rightURL != nil && fm.fileExists(atPath: item.rightURL!.path)) ? item.rightURL! : (fm.fileExists(atPath: targetRight.path) ? targetRight : nil) else {
                    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: targetRight.path])
                }
                let parent = targetLeft.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                let stagingURL = parent.appendingPathComponent(".nautica-sync-" + UUID().uuidString)
                try fm.copyItem(at: source, to: stagingURL)
                defer { try? fm.removeItem(at: stagingURL) }
                let exists = (try? fm.attributesOfItem(atPath: targetLeft.path)) != nil
                let flags: UInt32 = exists ? 0 : UInt32(RENAME_EXCL)
                guard renamex_np(stagingURL.path, targetLeft.path, flags) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: targetLeft.path])
                }
                copiedCount += 1

            case .deleteRight:
                if fm.fileExists(atPath: targetRight.path) {
                    try fm.removeItem(at: targetRight)
                    deletedCount += 1
                }

            case .deleteLeft:
                if fm.fileExists(atPath: targetLeft.path) {
                    try fm.removeItem(at: targetLeft)
                    deletedCount += 1
                }

            case .skip:
                break
            }
        }

        return (copiedCount, deletedCount)
    }
}
