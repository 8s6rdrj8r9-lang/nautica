import Foundation
import CryptoKit

/// Supported cryptographic hash algorithms.
public enum ChecksumAlgorithm: String, CaseIterable, Sendable, Identifiable {
    case sha256 = "SHA-256"
    case md5 = "MD5"
    case sha1 = "SHA-1"

    public var id: String { rawValue }
}

/// High-performance streaming checksum calculator supporting SHA-256, MD5, and SHA-1.
/// Reads files in chunks to ensure low memory footprint on arbitrarily large files.
public final class ChecksumService: Sendable {
    public static let shared = ChecksumService()

    /// Default buffer size for streaming file hashing (256 KB).
    public static let defaultBufferSize: Int = 256 * 1024

    private init() {}

    // MARK: - Streaming Checksum Calculation

    /// Computes SHA-256 hash string (lowercase hex) for the given file URL.
    public func computeSHA256(url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        try await computeHash(url: url, algorithm: .sha256, progress: progress)
    }

    /// Computes MD5 hash string (lowercase hex) for the given file URL.
    public func computeMD5(url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        try await computeHash(url: url, algorithm: .md5, progress: progress)
    }

    /// Computes SHA-1 hash string (lowercase hex) for the given file URL.
    public func computeSHA1(url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        try await computeHash(url: url, algorithm: .sha1, progress: progress)
    }

    /// Computes multiple hashes concurrently or in a single streaming pass for a file.
    public func computeHashes(
        url: URL,
        algorithms: [ChecksumAlgorithm] = [.sha256, .md5],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [ChecksumAlgorithm: String] {
        guard !algorithms.isEmpty else { return [:] }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        var sha256Hasher = algorithms.contains(.sha256) ? SHA256() : nil
        var md5Hasher = algorithms.contains(.md5) ? Insecure.MD5() : nil
        var sha1Hasher = algorithms.contains(.sha1) ? Insecure.SHA1() : nil

        var bytesReadTotal: Int64 = 0
        let bufferSize = Self.defaultBufferSize

        while !Task.isCancelled {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }

            sha256Hasher?.update(data: data)
            md5Hasher?.update(data: data)
            sha1Hasher?.update(data: data)

            bytesReadTotal += Int64(data.count)
            if fileSize > 0, let progress {
                let fraction = min(1.0, Double(bytesReadTotal) / Double(fileSize))
                progress(fraction)
            }
        }

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        var results: [ChecksumAlgorithm: String] = [:]
        if let h = sha256Hasher {
            results[.sha256] = h.finalize().map { String(format: "%02x", $0) }.joined()
        }
        if let h = md5Hasher {
            results[.md5] = h.finalize().map { String(format: "%02x", $0) }.joined()
        }
        if let h = sha1Hasher {
            results[.sha1] = h.finalize().map { String(format: "%02x", $0) }.joined()
        }

        return results
    }

    /// Computes a single hash algorithm in streaming chunks.
    public func computeHash(
        url: URL,
        algorithm: ChecksumAlgorithm,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let results = try await computeHashes(url: url, algorithms: [algorithm], progress: progress)
        guard let hash = results[algorithm] else {
            throw NSError(domain: "ChecksumService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compute \(algorithm.rawValue) hash"])
        }
        return hash
    }

    // MARK: - Prefix Partial Hashing (For Fast Pre-Filtering)

    /// Reads up to `bytes` from the start of a file and returns its SHA-256 hash.
    /// Useful for quick elimination of dissimilar files of identical length.
    public func computePrefixHash(url: URL, bytes: Int = 8192) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: bytes)
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Verification & Normalization

    /// Normalizes a checksum string by stripping whitespace, colons, and hyphens, and converting to lowercase.
    public static func normalize(hash: String) -> String {
        hash.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    /// Verifies if a given hash string matches the calculated checksum for a file.
    public func verify(
        url: URL,
        againstHash candidateHash: String,
        algorithm: ChecksumAlgorithm = .sha256
    ) async throws -> Bool {
        let normalizedCandidate = Self.normalize(hash: candidateHash)
        guard !normalizedCandidate.isEmpty else { return false }

        let calculatedHash = try await computeHash(url: url, algorithm: algorithm)
        return Self.normalize(hash: calculatedHash) == normalizedCandidate
    }
}
