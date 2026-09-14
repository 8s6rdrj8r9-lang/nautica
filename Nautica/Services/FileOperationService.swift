import AppKit
import Foundation
import Darwin

/// Outcome of a batch file operation: per-item success (with the final,
/// possibly auto-renamed URL) or failure (with its error).
struct FileOperationResult {
    struct Transfer {
        let original: URL
        let destination: URL
    }

    var transfers: [Transfer] = []
    var succeeded: [URL] { transfers.map(\.destination) }
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
        await withTaskCancellationHandler {
            transfer(urls, to: destination, move: false, progress: progress)
        } onCancel: {
            progress.cancel()
        }
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
                    for url in urls {
                        if let destination = trashed[url] {
                            result.transfers.append(.init(original: url, destination: destination))
                        } else {
                            result.failed.append((url, error ?? CocoaError(.fileWriteUnknown)))
                        }
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Restore exact original paths. A collision fails without replacing either item.
    func restoreItems(_ transfers: [FileOperationResult.Transfer]) async -> FileOperationResult {
        var result = FileOperationResult()
        for transfer in transfers {
            do {
                try coordinateMove(from: transfer.destination, to: transfer.original)
                result.transfers.append(.init(original: transfer.destination, destination: transfer.original))
            } catch {
                result.failed.append((transfer.destination, error))
            }
        }
        return result
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

    /// Renames multiple items sequentially, recording transfers for undo.
    func renameItems(_ renames: [(url: URL, newName: String)], progress: Progress? = nil) async -> FileOperationResult {
        var result = FileOperationResult()
        progress?.totalUnitCount = Int64(renames.count)
        progress?.completedUnitCount = 0

        for pair in renames {
            guard progress?.isCancelled != true else { break }
            let trimmed = pair.newName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != pair.url.lastPathComponent else {
                progress?.completedUnitCount += 1
                continue
            }
            let target = pair.url.deletingLastPathComponent().appendingPathComponent(trimmed)
            if FileManager.default.fileExists(atPath: target.path) {
                result.failed.append((pair.url, NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)))
                progress?.completedUnitCount += 1
                continue
            }
            do {
                try coordinateMove(from: pair.url, to: target)
                result.transfers.append(.init(original: pair.url, destination: target))
            } catch {
                result.failed.append((pair.url, error))
            }
            progress?.completedUnitCount += 1
        }
        return result
    }

    // MARK: - Private

    private func transfer(_ urls: [URL], to destination: URL, move: Bool, progress: Progress) -> FileOperationResult {
        var result = FileOperationResult()
        let sizes = urls.map { allocatedSize(of: $0, progress: progress) }
        progress.totalUnitCount = max(1, sizes.reduce(0, +))
        progress.completedUnitCount = 0

        for (url, size) in zip(urls, sizes) {
            guard !progress.isCancelled, !Task.isCancelled else {
                result.failed.append((url, CancellationError()))
                continue
            }
            let target = url.nonCollidingURL(in: destination)
            let completedBeforeItem = progress.completedUnitCount
            do {
                if move {
                    try coordinateMove(from: url, to: target)
                } else {
                    try coordinateCopy(from: url, to: target, progress: progress)
                }
                result.transfers.append(.init(original: url, destination: target))
            } catch {
                result.failed.append((url, error))
            }
            if !progress.isCancelled { progress.completedUnitCount = completedBeforeItem + size }
        }
        return result
    }

    private func coordinateCopy(from source: URL, to target: URL, progress: Progress) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source, options: [],
            writingItemAt: target, options: .forReplacing,
            error: &coordinationError
        ) { source, target in
            do {
                try stagedCopy(from: source, to: target, progress: progress)
            } catch {
                operationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    /// Copy into a private sibling directory, then publish without replacing an existing path.
    /// Failure cleanup only touches the staging directory created by this operation.
    private func stagedCopy(from source: URL, to target: URL, progress: Progress) throws {
        let fm = FileManager.default
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let parent = target.deletingLastPathComponent()
        let parentPath = parent.resolvingSymlinksInPath().standardizedFileURL.path
        if (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
           parentPath == sourcePath || parentPath.hasPrefix(sourcePath + "/") {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard !progress.isCancelled else { throw CancellationError() }
        let staging = parent.appendingPathComponent(".nautica-copy-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("item")
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }
        let context = CopyContext(progress: progress)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        let callback: copyfile_callback_t = { what, stage, state, _, _, pointer in
            guard let pointer else { return COPYFILE_QUIT }
            let context = Unmanaged<CopyContext>.fromOpaque(pointer).takeUnretainedValue()
            if context.progress.isCancelled { return COPYFILE_QUIT }
            if stage == COPYFILE_ERR {
                context.errorCode = errno
                return COPYFILE_QUIT
            }
            if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_START {
                context.lastCopied = 0
            }
            if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                    context.progress.completedUnitCount += max(0, copied - context.lastCopied)
                    context.lastCopied = copied
                }
            }
            return context.progress.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), pointer)
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        let status = withExtendedLifetime(context) {
            copyfile(source.path, temporary.path, state,
                     copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL))
        }
        let errorCode = context.errorCode ?? errno
        guard !progress.isCancelled else { throw CancellationError() }
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode),
                          userInfo: [NSFilePathErrorKey: source.path])
        }
        // Both paths are on the same volume; RENAME_EXCL also rejects dangling symlinks.
        guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    private final class CopyContext {
        let progress: Progress
        var lastCopied: off_t = 0
        var errorCode: Int32?
        init(progress: Progress) { self.progress = progress }
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
    private func allocatedSize(of url: URL, progress: Progress) -> Int64 {
        guard !progress.isCancelled else { return 1 }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else {
            return 1
        }
        guard values.isDirectory == true else {
            return max(1, Int64(values.fileSize ?? 0))
        }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let child as URL in enumerator {
                if progress.isCancelled { break }
                total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return max(1, total)
    }
}
