import Foundation

/// Represents a single file identified as a candidate or duplicate.
public struct DuplicateFileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let path: String
    public let fileSize: Int64
    public let dateModified: Date
    public let dateCreated: Date

    public var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public init(url: URL, fileSize: Int64, dateModified: Date, dateCreated: Date) {
        self.url = url
        self.name = url.lastPathComponent
        self.path = url.path(percentEncoded: false)
        self.fileSize = fileSize
        self.dateModified = dateModified
        self.dateCreated = dateCreated
    }
}

/// A cluster of two or more identical files sharing the exact same byte content and checksum.
public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let hash: String
    public let fileSize: Int64
    public var files: [DuplicateFileItem]

    public var reclaimableBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return Int64(files.count - 1) * fileSize
    }

    public var displayReclaimable: String {
        ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
    }

    public static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.hash == rhs.hash && lhs.fileSize == rhs.fileSize && lhs.files == rhs.files
    }
}

/// Smart rule presets for automatic duplicate selection.
public enum DuplicateSelectionRule: String, CaseIterable, Identifiable, Sendable {
    case keepOldest = "Keep Oldest"
    case keepNewest = "Keep Newest"
    case keepFirst = "Keep First Found"
    case deselectAll = "Deselect All"

    public var id: String { rawValue }
}

/// Progress state reported during a duplicate scanning operation.
public struct DuplicateScanProgress: Sendable {
    public enum Phase: String, Sendable {
        case discovering = "Discovering Files..."
        case groupingBySize = "Analyzing File Sizes..."
        case prefixHashing = "Quick Hash Pre-filtering..."
        case fullHashing = "Verifying Checksums..."
        case complete = "Scan Complete"
    }

    public let phase: Phase
    public let filesScanned: Int
    public let totalFilesFound: Int
    public let confirmedGroups: Int
    public let reclaimableBytesFound: Int64

    public var percentComplete: Double {
        guard totalFilesFound > 0 else { return 0 }
        return min(1.0, Double(filesScanned) / Double(totalFilesFound))
    }
}

/// High-performance duplicate file finder engine utilizing a 3-tier filtration pipeline:
/// 1. File Size Clustering (discards unique-size files without reading disk contents)
/// 2. Prefix Hashing (checks first 8 KB to eliminate false matches quickly)
/// 3. Full Cryptographic SHA-256 Hashing (verifies exact byte equality)
public final class DuplicateFinderService: Sendable {
    public static let shared = DuplicateFinderService()

    private init() {}

    // MARK: - Duplicate Scan Pipeline

    /// Scans the target directory recursively and returns all confirmed duplicate groups.
    public func scan(
        directory: URL,
        progressHandler: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async throws -> [DuplicateGroup] {
        let fileManager = FileManager.default

        // Step 1: Recursive File Discovery
        progressHandler?(DuplicateScanProgress(
            phase: .discovering,
            filesScanned: 0,
            totalFilesFound: 0,
            confirmedGroups: 0,
            reclaimableBytesFound: 0
        ))

        var allFiles: [DuplicateFileItem] = []
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { throw CancellationError() }

            // Skip hidden or system files
            if fileURL.lastPathComponent.hasPrefix(".") { continue }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  values.isPackage != true,
                  let size = values.fileSize,
                  size > 0 else {
                continue
            }

            let modified = values.contentModificationDate ?? Date()
            let created = values.creationDate ?? modified
            allFiles.append(DuplicateFileItem(
                url: fileURL,
                fileSize: Int64(size),
                dateModified: modified,
                dateCreated: created
            ))
        }

        let totalFiles = allFiles.count
        progressHandler?(DuplicateScanProgress(
            phase: .groupingBySize,
            filesScanned: 0,
            totalFilesFound: totalFiles,
            confirmedGroups: 0,
            reclaimableBytesFound: 0
        ))

        // Step 2: Tier 1 - Group by Exact File Size
        var sizeGroups: [Int64: [DuplicateFileItem]] = [:]
        for file in allFiles {
            sizeGroups[file.fileSize, default: []].append(file)
        }
        // Discard any size that only has 1 file
        let sizeCandidates = sizeGroups.filter { $0.value.count > 1 }

        var candidateFiles = sizeCandidates.values.flatMap { $0 }
        let candidateCount = candidateFiles.count

        // Step 3: Tier 2 - Prefix Hashing (First 8 KB)
        var prefixGroups: [String: [DuplicateFileItem]] = [:]
        var processedCount = 0

        for file in candidateFiles {
            guard !Task.isCancelled else { throw CancellationError() }

            let prefixHash = (try? ChecksumService.shared.computePrefixHash(url: file.url, bytes: 8192)) ?? UUID().uuidString
            let key = "\(file.fileSize)_\(prefixHash)"
            prefixGroups[key, default: []].append(file)

            processedCount += 1
            if processedCount % 20 == 0 || processedCount == candidateCount {
                progressHandler?(DuplicateScanProgress(
                    phase: .prefixHashing,
                    filesScanned: processedCount,
                    totalFilesFound: candidateCount,
                    confirmedGroups: 0,
                    reclaimableBytesFound: 0
                ))
            }
        }

        // Discard prefix groups with count < 2
        let prefixCandidates = prefixGroups.filter { $0.value.count > 1 }
        let fullHashCandidates = prefixCandidates.values.flatMap { $0 }
        let fullHashTotal = fullHashCandidates.count

        // Step 4: Tier 3 - Full SHA-256 Verification
        var verifiedGroups: [String: [DuplicateFileItem]] = [:]
        var verifiedCount = 0
        var currentReclaimable: Int64 = 0

        for file in fullHashCandidates {
            guard !Task.isCancelled else { throw CancellationError() }

            let fullHash = (try? await ChecksumService.shared.computeSHA256(url: file.url)) ?? UUID().uuidString
            let groupKey = "\(file.fileSize)_\(fullHash)"
            verifiedGroups[groupKey, default: []].append(file)

            verifiedCount += 1
            if verifiedCount % 5 == 0 || verifiedCount == fullHashTotal {
                let confirmed = verifiedGroups.filter { $0.value.count > 1 }
                currentReclaimable = confirmed.reduce(Int64(0)) { total, pair in
                    let groupFiles = pair.value
                    guard groupFiles.count > 1 else { return total }
                    return total + Int64(groupFiles.count - 1) * (groupFiles.first?.fileSize ?? 0)
                }

                progressHandler?(DuplicateScanProgress(
                    phase: .fullHashing,
                    filesScanned: verifiedCount,
                    totalFilesFound: fullHashTotal,
                    confirmedGroups: confirmed.count,
                    reclaimableBytesFound: currentReclaimable
                ))
            }
        }

        // Step 5: Assemble Final DuplicateGroups
        var finalGroups: [DuplicateGroup] = []
        for (_, groupFiles) in verifiedGroups where groupFiles.count > 1 {
            if let first = groupFiles.first {
                let fullHash = (try? await ChecksumService.shared.computeSHA256(url: first.url)) ?? ""
                finalGroups.append(DuplicateGroup(
                    hash: fullHash,
                    fileSize: first.fileSize,
                    files: groupFiles
                ))
            }
        }

        // Sort groups by reclaimable bytes descending (largest space savings first)
        finalGroups.sort { $0.reclaimableBytes > $1.reclaimableBytes }

        let totalReclaimable = finalGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        progressHandler?(DuplicateScanProgress(
            phase: .complete,
            filesScanned: fullHashTotal,
            totalFilesFound: fullHashTotal,
            confirmedGroups: finalGroups.count,
            reclaimableBytesFound: totalReclaimable
        ))

        return finalGroups
    }

    // MARK: - Smart Selection Rules

    /// Applies a selection rule to mark duplicate files for removal while preserving one copy.
    public static func applyRule(_ rule: DuplicateSelectionRule, to groups: [DuplicateGroup]) -> Set<URL> {
        var selectedURLs = Set<URL>()

        switch rule {
        case .keepOldest:
            for group in groups {
                let sorted = group.files.sorted { a, b in
                    if a.dateCreated != b.dateCreated {
                        return a.dateCreated < b.dateCreated
                    }
                    return a.dateModified < b.dateModified
                }
                // Keep index 0 (oldest), select all others for trashing
                for item in sorted.dropFirst() {
                    selectedURLs.insert(item.url)
                }
            }

        case .keepNewest:
            for group in groups {
                let sorted = group.files.sorted { a, b in
                    if a.dateModified != b.dateModified {
                        return a.dateModified > b.dateModified
                    }
                    return a.dateCreated > b.dateCreated
                }
                // Keep index 0 (newest), select all others for trashing
                for item in sorted.dropFirst() {
                    selectedURLs.insert(item.url)
                }
            }

        case .keepFirst:
            for group in groups {
                // Keep the first item in the group, select all others
                for item in group.files.dropFirst() {
                    selectedURLs.insert(item.url)
                }
            }

        case .deselectAll:
            selectedURLs.removeAll()
        }

        return selectedURLs
    }
}
