import AppKit
import Foundation
import Security

/// Algorithm options for cryptographic file shredding and secure data destruction.
enum ShredAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case zeroFill = "zeroFill"
    case dodStandard = "dodStandard"
    case gutmannLite = "gutmannLite"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zeroFill:
            return "1-Pass Zero Fill"
        case .dodStandard:
            return "3-Pass US DoD 5220.22-M"
        case .gutmannLite:
            return "7-Pass Cryptographic Overwrite"
        }
    }

    var passes: Int {
        switch self {
        case .zeroFill: return 1
        case .dodStandard: return 3
        case .gutmannLite: return 7
        }
    }

    var summary: String {
        switch self {
        case .zeroFill:
            return "Overwrites file blocks with zeros before truncation and unlinking. Fast sanitization."
        case .dodStandard:
            return "Overwrites with CSPRNG random bytes, binary ones (0xFF), and zeros (0x00) with forced cache flushes."
        case .gutmannLite:
            return "Performs 7 thorough passes with multi-layered pseudo-random data and bit inversions."
        }
    }
}

/// Real-time progress state during secure file shredding.
struct ShredProgress: Sendable {
    var filesProcessed: Int = 0
    var totalFiles: Int = 0
    var bytesProcessed: Int64 = 0
    var totalBytes: Int64 = 0
    var currentItemName: String = ""
    var currentPass: Int = 0
    var totalPasses: Int = 0

    var fractionalProgress: Double {
        guard totalBytes > 0 else {
            guard totalFiles > 0 else { return 1.0 }
            return Double(filesProcessed) / Double(totalFiles)
        }
        return min(1.0, max(0.0, Double(bytesProcessed) / Double(totalBytes)))
    }
}

/// Service that performs multi-pass cryptographic file shredding, POSIX buffer flushes,
/// file truncation, directory entry filename obfuscation, and unlinking.
final class SecureFileDeletionService: @unchecked Sendable {
    static let shared = SecureFileDeletionService()

    private init() {}

    private let bufferSize = 64 * 1024 // 64 KB write chunks

    /// Estimates the total number of files and aggregate bytes for the given list of URLs.
    func calculateMetrics(for urls: [URL]) -> (totalFiles: Int, totalBytes: Int64) {
        let fm = FileManager.default
        var totalFiles = 0
        var totalBytes: Int64 = 0

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: []
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    totalFiles += 1
                    if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                       values.isRegularFile == true {
                        totalBytes += Int64(values.fileSize ?? 0)
                    }
                }
                totalFiles += 1 // Count the container folder itself
            } else {
                totalFiles += 1
                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    totalBytes += size
                }
            }
        }
        return (totalFiles, totalBytes)
    }

    /// Securely shreds files and folders using the specified algorithm with live progress reporting.
    func secureDelete(
        urls: [URL],
        algorithm: ShredAlgorithm = .dodStandard,
        onProgress: ((ShredProgress) -> Void)? = nil
    ) async throws {
        let metrics = calculateMetrics(for: urls)
        var progress = ShredProgress(
            filesProcessed: 0,
            totalFiles: max(1, metrics.totalFiles),
            bytesProcessed: 0,
            totalBytes: max(1, metrics.totalBytes * Int64(algorithm.passes)),
            currentItemName: "",
            currentPass: 0,
            totalPasses: algorithm.passes
        )

        for url in urls {
            try Task.checkCancellation()
            try shredItemRecursively(
                at: url,
                algorithm: algorithm,
                progress: &progress,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Internal Shredding

    private func shredItemRecursively(
        at url: URL,
        algorithm: ShredAlgorithm,
        progress: inout ShredProgress,
        onProgress: ((ShredProgress) -> Void)?
    ) throws {
        let fm = FileManager.default

        var statInfo = stat()
        guard lstat(url.path, &statInfo) == 0 else { return }

        // If item is a symbolic link, never follow it or truncate its target.
        // Simply unlink the symlink itself.
        if (statInfo.st_mode & S_IFMT) == S_IFLNK {
            unlink(url.path)
            progress.filesProcessed += 1
            onProgress?(progress)
            return
        }

        // If item is a hard link with multiple links, unlink without shredding shared inode
        if (statInfo.st_mode & S_IFMT) == S_IFREG && statInfo.st_nlink > 1 {
            unlink(url.path)
            progress.filesProcessed += 1
            onProgress?(progress)
            return
        }

        let isDir = (statInfo.st_mode & S_IFMT) == S_IFDIR
        if isDir {
            // Shred all children first (bottom-up)
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            for child in contents {
                try Task.checkCancellation()
                try shredItemRecursively(at: child, algorithm: algorithm, progress: &progress, onProgress: onProgress)
            }
            // Obfuscate directory name and remove
            let scrambledURL = try scrambleName(at: url)
            try fm.removeItem(at: scrambledURL)
            progress.filesProcessed += 1
            onProgress?(progress)
        } else {
            try shredSingleFile(at: url, algorithm: algorithm, progress: &progress, onProgress: onProgress)
        }
    }

    private func shredSingleFile(
        at url: URL,
        algorithm: ShredAlgorithm,
        progress: inout ShredProgress,
        onProgress: ((ShredProgress) -> Void)?
    ) throws {
        progress.currentItemName = url.lastPathComponent
        onProgress?(progress)

        let path = url.path
        let fd = open(path, O_RDWR | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ELOOP || errno == EMLINK {
                // Symbolic link encountered via open: unlink safely without touching target
                unlink(path)
                progress.filesProcessed += 1
                onProgress?(progress)
                return
            }
            throw NSError(
                domain: "SecureFileDeletionService",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open \(url.lastPathComponent) for shredding: \(String(cString: strerror(errno)))"]
            )
        }

        var isOpen = true
        defer {
            if isOpen { close(fd) }
        }

        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            throw NSError(
                domain: "SecureFileDeletionService",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Failed to stat \(url.lastPathComponent)"]
            )
        }

        let fileSize = statInfo.st_size

        if fileSize > 0 {
            let passes = algorithm.passes
            for passIndex in 1...passes {
                try Task.checkCancellation()
                progress.currentPass = passIndex
                onProgress?(progress)

                // Seek back to start
                lseek(fd, 0, SEEK_SET)

                var remaining = fileSize
                while remaining > 0 {
                    let chunk = min(Int(remaining), bufferSize)
                    let data = patternForPass(passIndex: passIndex, totalPasses: passes, algorithm: algorithm, byteCount: chunk)

                    try data.withUnsafeBytes { rawBuffer in
                        guard let ptr = rawBuffer.baseAddress else { return }
                        let written = write(fd, ptr, chunk)
                        if written < 0 {
                            throw NSError(
                                domain: "SecureFileDeletionService",
                                code: Int(errno),
                                userInfo: [NSLocalizedDescriptionKey: "Write failed during shredding of \(url.lastPathComponent)"]
                            )
                        }
                    }

                    remaining -= Int64(chunk)
                    progress.bytesProcessed += Int64(chunk)
                    onProgress?(progress)
                }

                // Force full physical disk flush bypassing macOS drive write caches
                fcntl(fd, F_FULLFSYNC)
            }

            // Truncate to zero bytes
            ftruncate(fd, 0)
            fcntl(fd, F_FULLFSYNC)
        }

        // Close descriptor before renaming & unlinking
        if isOpen {
            isOpen = false
            close(fd)
        }

        // Scramble filename in directory entry to destroy filesystem metadata traces
        let scrambledURL = try scrambleName(at: url)
        try FileManager.default.removeItem(at: scrambledURL)

        progress.filesProcessed += 1
        onProgress?(progress)
    }

    /// Obfuscates the filename with a randomized alphanumeric sequence before deletion.
    private func scrambleName(at url: URL) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let randomString = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let scrambledName = ".\(randomString).shredding"
        let scrambledURL = parent.appendingPathComponent(scrambledName)
        try FileManager.default.moveItem(at: url, to: scrambledURL)
        return scrambledURL
    }

    /// Generates pattern buffer for the given pass.
    private func patternForPass(
        passIndex: Int,
        totalPasses: Int,
        algorithm: ShredAlgorithm,
        byteCount: Int
    ) -> Data {
        switch algorithm {
        case .zeroFill:
            return Data(repeating: 0x00, count: byteCount)

        case .dodStandard:
            switch passIndex {
            case 1:
                // Pass 1: CSPRNG Random
                var data = Data(count: byteCount)
                _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, byteCount, $0.baseAddress!) }
                return data
            case 2:
                // Pass 2: Ones (0xFF)
                return Data(repeating: 0xFF, count: byteCount)
            default:
                // Pass 3: Zeros (0x00)
                return Data(repeating: 0x00, count: byteCount)
            }

        case .gutmannLite:
            if passIndex <= 4 {
                var data = Data(count: byteCount)
                _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, byteCount, $0.baseAddress!) }
                return data
            } else if passIndex == 5 {
                return Data(repeating: 0xAA, count: byteCount)
            } else if passIndex == 6 {
                return Data(repeating: 0x55, count: byteCount)
            } else {
                return Data(repeating: 0x00, count: byteCount)
            }
        }
    }
}
