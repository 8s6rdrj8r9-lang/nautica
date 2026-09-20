import AppKit
import Foundation

/// Cloud synchronization status for items stored in FileProvider / iCloud storage.
enum CloudSyncStatus: String, Sendable, Hashable {
    case notCloud
    case onlineOnly      // Dataless placeholder (bytes not downloaded)
    case downloading     // Currently in flight
    case downloaded      // Locally cached and available offline
    case conflict        // Unresolved sync conflict
}

/// Git working tree status for an item.
public enum GitFileState: String, Sendable, Hashable {
    case modified = "M"
    case added = "A"
    case untracked = "?"
    case deleted = "D"
    case renamed = "R"
    case conflict = "U"

    public var displayName: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added / Staged"
        case .untracked: return "Untracked"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .conflict: return "Conflict"
        }
    }

    public var badgeColor: NSColor {
        switch self {
        case .modified: return .systemOrange
        case .added: return .systemGreen
        case .untracked: return .systemBlue
        case .deleted: return .systemRed
        case .renamed: return .systemPurple
        case .conflict: return .systemYellow
        }
    }
}

/// Representation of a file or folder in the file system.
struct FileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let kind: String
    let cloudStatus: CloudSyncStatus
    let cloudProvider: CloudStorageProvider?
    let tags: [String]
    let gitStatus: GitFileState?

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        isDirectory: Bool,
        size: Int64?,
        modificationDate: Date?,
        creationDate: Date?,
        isHidden: Bool,
        kind: String,
        cloudStatus: CloudSyncStatus = .notCloud,
        cloudProvider: CloudStorageProvider? = nil,
        tags: [String] = [],
        gitStatus: GitFileState? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isHidden = isHidden
        self.kind = kind
        self.cloudStatus = cloudStatus
        self.cloudProvider = cloudProvider
        self.tags = tags
        self.gitStatus = gitStatus
    }

    var isCloudItem: Bool {
        cloudStatus != .notCloud || cloudProvider != nil
    }

    var isOnlineOnly: Bool {
        cloudStatus == .onlineOnly
    }

    var isDownloaded: Bool {
        cloudStatus == .downloaded
    }

    var canDownload: Bool {
        cloudStatus == .onlineOnly
    }

    var canEvict: Bool {
        cloudStatus == .downloaded
    }

    /// Parsed tag representations (name and color).
    var tagInfos: [FileTagInfo] {
        tags.map { FileTagInfo(rawName: $0) }
    }

    /// Unique macOS system color labels assigned to this item.
    var tagColors: [TagColor] {
        var result: [TagColor] = []
        for info in tagInfos {
            if let color = info.color, !result.contains(color) {
                result.append(color)
            }
        }
        return result
    }

    /// Lazily-loaded file icon (system icon for the file's type).
    var iconImage: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Whether this file is a macOS alias or symbolic link.
    var isAliasOrSymlink: Bool {
        FileOperationService.shared.resolveTarget(for: url) != nil
    }

    /// Resolves destination URL if this item is an alias or symlink.
    var resolvedTargetURL: URL? {
        FileOperationService.shared.resolveTarget(for: url)
    }
}
