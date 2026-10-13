import AppKit
import Foundation

/// Represents a mounted storage volume, APFS container, or external drive.
struct StorageVolume: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let usedCapacity: Int64
    let usageRatio: Double
    let fileSystemType: String
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isRootFileSystem: Bool
    let isReadOnly: Bool
    let isEncrypted: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        totalCapacity: Int64 = 0,
        availableCapacity: Int64 = 0,
        fileSystemType: String = "APFS",
        isInternal: Bool = true,
        isRemovable: Bool = false,
        isEjectable: Bool = false,
        isRootFileSystem: Bool = false,
        isReadOnly: Bool = false,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.totalCapacity = max(0, totalCapacity)
        self.availableCapacity = max(0, availableCapacity)
        let used = max(0, totalCapacity - availableCapacity)
        self.usedCapacity = used
        self.usageRatio = totalCapacity > 0 ? min(1.0, max(0.0, Double(used) / Double(totalCapacity))) : 0.0
        self.fileSystemType = fileSystemType
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isRootFileSystem = isRootFileSystem
        self.isReadOnly = isReadOnly
        self.isEncrypted = isEncrypted
    }

    var formattedTotal: String {
        guard totalCapacity > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var formattedAvailable: String {
        guard availableCapacity > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        guard usedCapacity > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var formattedSummary: String {
        if totalCapacity > 0 {
            return "\(formattedAvailable) available of \(formattedTotal)"
        }
        return name
    }

    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Category breakdown of storage usage for a given directory or volume.
struct StorageBreakdown: Sendable {
    var totalBytes: Int64 = 0
    var documentsBytes: Int64 = 0
    var mediaBytes: Int64 = 0
    var codeBytes: Int64 = 0
    var archivesBytes: Int64 = 0
    var otherBytes: Int64 = 0

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

/// Observable model tracking system storage volumes, available capacity, and disk metrics.
@MainActor
@Observable
final class StorageModel {
    static let shared = StorageModel()

    var volumes: [StorageVolume] = []
    var isLoading: Bool = false
    var lastRefreshed: Date = .now

    var rootVolume: StorageVolume? {
        volumes.first { $0.isRootFileSystem || $0.url.path == "/" }
    }

    private nonisolated(unsafe) var mountObserver: NSObjectProtocol?
    private nonisolated(unsafe) var unmountObserver: NSObjectProtocol?

    init() {
        refresh()
        setupNotificationObservers()
    }

    deinit {
        if let mountObserver {
            NotificationCenter.default.removeObserver(mountObserver)
        }
        if let unmountObserver {
            NotificationCenter.default.removeObserver(unmountObserver)
        }
    }

    private func setupNotificationObservers() {
        mountObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        unmountObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Enumerates all mounted volumes and updates state.
    func refresh() {
        isLoading = true
        defer {
            isLoading = false
            lastRefreshed = .now
        }

        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsRootFileSystemKey,
            .volumeIsReadOnlyKey,
            .volumeTypeNameKey,
            .volumeIsEncryptedKey
        ]
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options) ?? []

        var detectedVolumes: [StorageVolume] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeLocalizedName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let isInternal = values.volumeIsInternal ?? true
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            let isReadOnly = values.volumeIsReadOnly ?? false
            let isEncrypted = values.volumeIsEncrypted ?? false
            let typeName = values.volumeTypeName ?? "APFS"

            let volume = StorageVolume(
                url: url,
                name: isRoot ? "Macintosh HD" : name,
                totalCapacity: total,
                availableCapacity: available,
                fileSystemType: typeName,
                isInternal: isInternal,
                isRemovable: isRemovable,
                isEjectable: isEjectable,
                isRootFileSystem: isRoot,
                isReadOnly: isReadOnly,
                isEncrypted: isEncrypted
            )
            detectedVolumes.append(volume)
        }

        // Ensure root filesystem is always present
        if !detectedVolumes.contains(where: { $0.url.path == "/" }) {
            let rootURL = URL(fileURLWithPath: "/")
            let values = try? rootURL.resourceValues(forKeys: Set(keys))
            let total = Int64(values?.volumeTotalCapacity ?? 0)
            let available = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
            let rootVol = StorageVolume(
                url: rootURL,
                name: "Macintosh HD",
                totalCapacity: total,
                availableCapacity: available,
                fileSystemType: values?.volumeTypeName ?? "APFS",
                isInternal: true,
                isRemovable: false,
                isEjectable: false,
                isRootFileSystem: true,
                isReadOnly: false,
                isEncrypted: values?.volumeIsEncrypted ?? false
            )
            detectedVolumes.insert(rootVol, at: 0)
        }

        self.volumes = detectedVolumes
    }

    /// Returns the StorageVolume that hosts the given URL.
    func volume(for url: URL) -> StorageVolume? {
        let standardPath = url.standardizedFileURL.path
        // Sort by path length descending so more specific mount paths match first
        let sorted = volumes.sorted { $0.url.path.count > $1.url.path.count }
        return sorted.first { volume in
            let volPath = volume.url.standardizedFileURL.path
            return standardPath == volPath || standardPath.hasPrefix(volPath + "/")
        } ?? rootVolume
    }

    /// Safely unmounts and ejects the given volume.
    func eject(volume: StorageVolume) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        refresh()
    }
}
