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

    /// Whether any item was skipped due to cancellation.
    var isCancelled: Bool {
        failed.contains { $0.1 is CancellationError }
    }

    /// URLs whose transfer was cancelled or skipped.
    var cancelledSources: [URL] {
        failed.compactMap { $0.1 is CancellationError ? $0.0 : nil }
    }
}

/// Copy, move, trash, and rename (Prompt 10). All work runs on this actor,
/// off the main thread; every mutation goes through `NSFileCoordinator`.
actor FileOperationService {
    static let shared = FileOperationService()

    /// Rolls back transfers recorded in `result`, returning destination to its pre-operation state.
    func rollback(result: FileOperationResult) async {
        let fm = FileManager.default
        for transfer in result.transfers.reversed() {
            try? fm.removeItem(at: transfer.destination)
        }
    }

    // MARK: - Copy / Move

    /// Detects whether any source items would collide with existing items in destination.
    nonisolated func detectCollisions(sources: [URL], destination: URL) -> [FileConflict] {
        var conflicts: [FileConflict] = []
        let fm = FileManager.default
        for source in sources {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                conflicts.append(FileConflict(sourceURL: source, destinationURL: target))
            }
        }
        return conflicts
    }

    /// Copies each URL into `destination`, respecting conflict resolutions or auto-renaming.
    /// Progress counts bytes; cancelling skips remaining items and removes
    /// the in-flight partial copy.
    func copyItems(
        _ urls: [URL],
        to destination: URL,
        progress: Progress,
        resolutions: [URL: ConflictResolutionChoice] = [:]
    ) async -> FileOperationResult {
        await withTaskCancellationHandler {
            transfer(urls, to: destination, move: false, progress: progress, resolutions: resolutions)
        } onCancel: {
            progress.cancel()
        }
    }

    /// Moves each URL into `destination`, respecting conflict resolutions or auto-renaming.
    func moveItems(
        _ urls: [URL],
        to destination: URL,
        progress: Progress,
        resolutions: [URL: ConflictResolutionChoice] = [:]
    ) async -> FileOperationResult {
        transfer(urls, to: destination, move: true, progress: progress, resolutions: resolutions)
    }

    // MARK: - Aliases

    /// Creates macOS Bookmark Aliases for the specified URLs in the destination directory.
    func makeAliases(for urls: [URL], in destination: URL) async -> FileOperationResult {
        var result = FileOperationResult()
        let fm = FileManager.default
        for url in urls {
            let nameWithoutExt = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var aliasName = ext.isEmpty ? "\(nameWithoutExt) alias" : "\(nameWithoutExt) alias.\(ext)"
            var target = destination.appendingPathComponent(aliasName)
            var counter = 2
            while fm.fileExists(atPath: target.path) {
                aliasName = ext.isEmpty ? "\(nameWithoutExt) alias \(counter)" : "\(nameWithoutExt) alias \(counter).\(ext)"
                target = destination.appendingPathComponent(aliasName)
                counter += 1
            }

            do {
                let bookmarkData = try url.bookmarkData(
                    options: .suitableForBookmarkFile,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try URL.writeBookmarkData(bookmarkData, to: target)
                result.transfers.append(.init(original: url, destination: target))
            } catch {
                result.failed.append((url, error))
            }
        }
        return result
    }

    /// Resolves an alias file or symbolic link to its original destination URL.
    nonisolated func resolveTarget(for url: URL) -> URL? {
        let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                let destURL = URL(fileURLWithPath: dest, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
                return destURL
            }
        }
        if values?.isAliasFile == true || (try? URL.bookmarkData(withContentsOf: url)) != nil {
            if let data = try? URL.bookmarkData(withContentsOf: url) {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    return resolved.standardizedFileURL
                }
            }
        }
        return nil
    }

    // MARK: - Trash

    /// Moves items to the Trash via NSWorkspace (with the Finder sound).
    /// `succeeded` holds the *new* URLs inside the Trash, in input order,
    /// so callers can offer Undo.
    func trashItems(_ urls: [URL]) async -> FileOperationResult {
        let result: FileOperationResult = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle(urls) { trashed, error in
                    var res = FileOperationResult()
                    for url in urls {
                        if let destination = trashed[url] {
                            res.transfers.append(.init(original: url, destination: destination))
                        } else {
                            res.failed.append((url, error ?? CocoaError(.fileWriteUnknown)))
                        }
                    }
                    continuation.resume(returning: res)
                }
            }
        }
        TrashOriginStore.shared.record(transfers: result.transfers)
        return result
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

    /// Duplicates the given URLs in place using standard macOS "copy" naming convention.
    func duplicateItems(_ urls: [URL], progress: Progress? = nil) async -> FileOperationResult {
        var result = FileOperationResult()
        progress?.totalUnitCount = Int64(urls.count)
        progress?.completedUnitCount = 0

        for url in urls {
            guard progress?.isCancelled != true else { break }
            let dest = Self.duplicateURL(for: url)
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                result.transfers.append(.init(original: url, destination: dest))
            } catch {
                result.failed.append((url, error))
            }
            progress?.completedUnitCount += 1
        }
        return result
    }

    /// Deletes the specified items (used for reversing/undoing copy and duplicate operations).
    func deleteItems(_ urls: [URL]) async -> FileOperationResult {
        var result = FileOperationResult()
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                result.transfers.append(.init(original: url, destination: url))
            } catch {
                result.failed.append((url, error))
            }
        }
        return result
    }

    /// Computes the standard Finder duplicate destination URL (e.g. "foo copy.ext", "foo copy 2.ext").
    static func duplicateURL(for original: URL) -> URL {
        let parent = original.deletingLastPathComponent()
        let ext = original.pathExtension
        let baseName = original.deletingPathExtension().lastPathComponent

        let fm = FileManager.default
        let regex = try? NSRegularExpression(pattern: #"^(.*?)( copy( \d+)?)?$"#, options: .caseInsensitive)
        var stem = baseName
        if let match = regex?.firstMatch(in: baseName, options: [], range: NSRange(location: 0, length: baseName.utf16.count)) {
            if let stemRange = Range(match.range(at: 1), in: baseName) {
                stem = String(baseName[stemRange])
            }
        }

        let candidateName1 = ext.isEmpty ? "\(stem) copy" : "\(stem) copy.\(ext)"
        let candidateURL1 = parent.appendingPathComponent(candidateName1)
        if !fm.fileExists(atPath: candidateURL1.path) {
            return candidateURL1
        }

        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) copy \(counter)" : "\(stem) copy \(counter).\(ext)"
            let candidateURL = parent.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
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

    private func transfer(
        _ urls: [URL],
        to destination: URL,
        move: Bool,
        progress: Progress,
        resolutions: [URL: ConflictResolutionChoice] = [:]
    ) -> FileOperationResult {
        var result = FileOperationResult()
        let sizes = urls.map { allocatedSize(of: $0, progress: progress) }
        progress.totalUnitCount = max(1, sizes.reduce(0, +))
        progress.completedUnitCount = 0

        for (url, size) in zip(urls, sizes) {
            guard !progress.isCancelled, !Task.isCancelled else {
                result.failed.append((url, CancellationError()))
                continue
            }

            let resolution = resolutions[url]
            if resolution == .stop {
                result.failed.append((url, CancellationError()))
                break
            }

            let target: URL
            let fm = FileManager.default
            let directTarget = destination.appendingPathComponent(url.lastPathComponent)
            let directExists = (try? fm.attributesOfItem(atPath: directTarget.path)) != nil
            let isReplacing = (resolution == .replace)

            if resolution == .replace {
                target = directTarget
            } else if resolution == .keepBoth {
                target = url.nonCollidingURL(in: destination)
            } else {
                target = directExists ? url.nonCollidingURL(in: destination) : directTarget
            }

            let completedBeforeItem = progress.completedUnitCount
            do {
                if move {
                    if isReplacing && directExists {
                        let backup = destination.appendingPathComponent(".nautica-displaced-" + UUID().uuidString)
                        try fm.moveItem(at: directTarget, to: backup)
                        do {
                            try coordinateMove(from: url, to: target)
                            try? fm.removeItem(at: backup)
                        } catch {
                            // Rollback displaced target on move failure
                            try? fm.moveItem(at: backup, to: directTarget)
                            throw error
                        }
                    } else {
                        try coordinateMove(from: url, to: target)
                    }
                } else {
                    try coordinateCopy(from: url, to: target, progress: progress, replacing: isReplacing)
                }
                result.transfers.append(.init(original: url, destination: target))
            } catch {
                result.failed.append((url, error))
            }
            if !progress.isCancelled { progress.completedUnitCount = completedBeforeItem + size }
        }
        return result
    }

    private func coordinateCopy(from source: URL, to target: URL, progress: Progress, replacing: Bool = false) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source, options: [],
            writingItemAt: target, options: replacing ? .forReplacing : [],
            error: &coordinationError
        ) { source, target in
            do {
                try stagedCopy(from: source, to: target, progress: progress, replacing: replacing)
            } catch {
                operationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    /// Copy into a private sibling directory, then publish without replacing an existing path unless replacing is explicitly requested.
    /// Failure cleanup only touches the staging directory created by this operation.
    private func stagedCopy(from source: URL, to target: URL, progress: Progress, replacing: Bool = false) throws {
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
        let publishFlags: UInt32 = replacing ? 0 : UInt32(RENAME_EXCL)
        guard renamex_np(temporary.path, target.path, publishFlags) == 0 else {
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
