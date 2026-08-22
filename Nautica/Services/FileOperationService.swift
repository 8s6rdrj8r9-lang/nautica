import AppKit
import Foundation

/// Outcome of a batch file operation: per-item success (with the final,
/// possibly auto-renamed URL) or failure (with its error).
struct FileOperationResult {
    var succeeded: [URL] = []
    var failed: [(URL, Error)] = []
}

/// Copy, move, trash, and rename (Prompt 10). All work runs on this actor,
/// off the main thread; every mutation goes through `NSFileCoordinator`.
actor FileOperationService {
    static let shared = FileOperationService()

    // MARK: - Copy / Move

    /// Copies each URL into `destination`, auto-renaming collisions.
    /// Progress counts bytes; cancelling skips remaining items and removes
    /// the in-flight partial copy.
    func copyItems(_ urls: [URL], to destination: URL, progress: Progress) async -> FileOperationResult {
        transfer(urls, to: destination, move: false, progress: progress)
    }

    /// Moves each URL into `destination`, auto-renaming collisions.
    func moveItems(_ urls: [URL], to destination: URL, progress: Progress) async -> FileOperationResult {
        transfer(urls, to: destination, move: true, progress: progress)
    }

    // MARK: - Trash

    /// Moves items to the Trash via NSWorkspace (with the Finder sound).
    /// `succeeded` holds the *new* URLs inside the Trash, in input order,
    /// so callers can offer Undo.
    func trashItems(_ urls: [URL]) async -> FileOperationResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(urls) { trashed, error in
                    var result = FileOperationResult()
                    if let error {
                        result.failed = urls.map { ($0, error) }
                    } else {
                        result.succeeded = urls.map { trashed[$0] ?? $0 }
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Rename

    /// Renames a single item in place, returning the new URL. Throws
    /// `NSFileWriteFileExistsError` if the new name is taken.
    func renameItem(at url: URL, to newName: String) async throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != url.lastPathComponent else { return url }
        let target = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
        }
        try coordinateMove(from: url, to: target)
        return target
    }

    // MARK: - Private

    private func transfer(_ urls: [URL], to destination: URL, move: Bool, progress: Progress) -> FileOperationResult {
        var result = FileOperationResult()
        let sizes = urls.map { allocatedSize(of: $0) }
        progress.totalUnitCount = max(1, sizes.reduce(0, +))
        progress.completedUnitCount = 0

        for (url, size) in zip(urls, sizes) {
            guard !progress.isCancelled, !Task.isCancelled else {
                result.failed.append((url, CancellationError()))
                continue
            }
            let target = url.nonCollidingURL(in: destination)
            do {
                if move {
                    try coordinateMove(from: url, to: target)
                } else {
                    try coordinateCopy(from: url, to: target)
                }
                result.succeeded.append(target)
            } catch {
                // Remove a partial copy so a cancelled/failed copy never
                // leaves half-written files behind.
                if !move { try? FileManager.default.removeItem(at: target) }
                result.failed.append((url, error))
            }
            progress.completedUnitCount += size
        }
        return result
    }

    private func coordinateCopy(from source: URL, to target: URL) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source, options: [],
            writingItemAt: target, options: .forReplacing,
            error: &coordinationError
        ) { source, target in
            do {
                try FileManager.default.copyItem(at: source, to: target)
            } catch {
                operationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private func coordinateMove(from source: URL, to target: URL) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: target, options: .forReplacing,
            error: &coordinationError
        ) { source, target in
            do {
                try FileManager.default.moveItem(at: source, to: target)
            } catch {
                operationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    /// Recursive byte count used for progress reporting.
    private func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else {
            return 1
        }
        guard values.isDirectory == true else {
            return Int64(values.fileSize ?? 0)
        }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let child as URL in enumerator {
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return max(1, total)
    }
}
