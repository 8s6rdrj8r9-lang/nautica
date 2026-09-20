import AppKit
import Foundation

/// Central service managing archive extraction, disk image mounting,
/// and password-protected ZIP creation.
final class ArchiveService {
    static let shared = ArchiveService()

    private init() {}

    static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "7z"
    ]

    static let diskImageExtensions: Set<String> = [
        "dmg", "iso"
    ]

    func isArchive(url: URL) -> Bool {
        Self.archiveExtensions.contains(url.pathExtension.lowercased())
    }

    func isDiskImage(url: URL) -> Bool {
        Self.diskImageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Extracts an archive into a clean destination directory.
    @discardableResult
    func extract(archiveURL: URL, destination: URL? = nil) async throws -> URL {
        let parentDir = archiveURL.deletingLastPathComponent()
        let rawBaseName = archiveURL.deletingPathExtension().lastPathComponent
        // Handle double extensions like .tar.gz
        let cleanBaseName = rawBaseName.hasSuffix(".tar") ? String(rawBaseName.dropLast(4)) : rawBaseName

        let targetDir: URL
        if let destination {
            targetDir = destination
        } else {
            let fm = FileManager.default
            var candidate = parentDir.appendingPathComponent(cleanBaseName)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = parentDir.appendingPathComponent("\(cleanBaseName) \(counter)")
                counter += 1
            }
            targetDir = candidate
        }

        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let ext = archiveURL.pathExtension.lowercased()
        let process = Process()

        if ext == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, targetDir.path]
        } else {
            // tar, tar.gz, tgz, tar.bz2, tbz, tar.xz, txz
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archiveURL.path, "-C", targetDir.path]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ArchiveService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Failed to extract archive '\(archiveURL.lastPathComponent)'"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return targetDir
    }

    /// Mounts a .dmg or .iso disk image using `hdiutil attach` and returns the mount point URL.
    func attachDiskImage(at url: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-plist", "-nobrowse", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus == 0,
                       let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                       let entities = plist["system-entities"] as? [[String: Any]] {
                        for entity in entities {
                            if let mountPoint = entity["mount-point"] as? String {
                                continuation.resume(returning: URL(fileURLWithPath: mountPoint))
                                return
                            }
                        }
                    }
                    continuation.resume(throwing: NSError(
                        domain: "ArchiveService",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Failed to attach disk image '\(url.lastPathComponent)'"]
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Creates a zip archive, optionally encrypted with a password.
    func createArchive(
        from urls: [URL],
        in destinationDir: URL,
        baseName: String? = nil,
        password: String? = nil
    ) async throws -> URL {
        guard !urls.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No items to archive"])
        }

        let archiveBase = baseName ?? (urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive")
        let fm = FileManager.default
        var outputURL = destinationDir.appendingPathComponent("\(archiveBase).zip")
        var counter = 2
        while fm.fileExists(atPath: outputURL.path) {
            outputURL = destinationDir.appendingPathComponent("\(archiveBase) \(counter).zip")
            counter += 1
        }

        // Determine working directory (parent of the first item)
        let workingDir = urls[0].deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDir
        var args = ["-q", "-r"]
        if let pwd = password, !pwd.isEmpty {
            args.append(contentsOf: ["-P", pwd])
        }
        args.append(outputURL.path)
        for url in urls {
            if url.deletingLastPathComponent().path == workingDir.path {
                args.append(url.lastPathComponent)
            } else {
                args.append(url.path)
            }
        }
        process.arguments = args

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ArchiveService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return outputURL
    }
}
