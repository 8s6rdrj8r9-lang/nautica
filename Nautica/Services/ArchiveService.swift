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

    // MARK: - Encrypted Disk Images & Encrypted Tarballs

    /// Returns whether the given URL points to an encrypted archive (.tar.gz.enc, .tgz.enc, or .enc).
    func isEncryptedArchive(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.gz.enc") || name.hasSuffix(".tgz.enc") || url.pathExtension.lowercased() == "enc"
    }

    /// Creates an AES-encrypted disk image (.dmg) from the given items.
    func createEncryptedDiskImage(
        from urls: [URL],
        in destinationDir: URL,
        baseName: String? = nil,
        password: String,
        encryption: VaultService.EncryptionAlgorithm = .aes256
    ) async throws -> URL {
        guard !urls.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No items to archive"])
        }
        guard !password.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Password cannot be empty"])
        }

        let archiveBase = baseName ?? (urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Encrypted Disk Image")
        let fm = FileManager.default
        var outputURL = destinationDir.appendingPathComponent("\(archiveBase).dmg")
        var counter = 2
        while fm.fileExists(atPath: outputURL.path) {
            outputURL = destinationDir.appendingPathComponent("\(archiveBase) \(counter).dmg")
            counter += 1
        }

        var sourceFolder: URL
        var temporaryStagingDir: URL? = nil

        if urls.count == 1, urls[0].hasDirectoryPath {
            sourceFolder = urls[0]
        } else {
            // Stage items into a temporary staging folder
            let staging = fm.temporaryDirectory.appendingPathComponent("NauticaDMGStage-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            temporaryStagingDir = staging
            sourceFolder = staging

            for itemURL in urls {
                var dest = staging.appendingPathComponent(itemURL.lastPathComponent)
                var disambiguation = 1
                let ext = itemURL.pathExtension
                let baseName = itemURL.deletingPathExtension().lastPathComponent
                while fm.fileExists(atPath: dest.path) {
                    let newName = ext.isEmpty ? "\(baseName) (\(disambiguation))" : "\(baseName) (\(disambiguation)).\(ext)"
                    dest = staging.appendingPathComponent(newName)
                    disambiguation += 1
                }
                try fm.copyItem(at: itemURL, to: dest)
            }
        }

        defer {
            if let temporaryStagingDir {
                try? fm.removeItem(at: temporaryStagingDir)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-srcfolder", sourceFolder.path,
            "-format", "UDZO",
            "-encryption", encryption.rawValue,
            "-stdinpass",
            outputURL.path
        ]

        let inPipe = Pipe()
        process.standardInput = inPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    let passwordData = "\(password)\n".data(using: .utf8) ?? Data()
                    inPipe.fileHandleForWriting.write(passwordData)
                    try? inPipe.fileHandleForWriting.close()

                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ArchiveService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create encrypted disk image (Exit code: \(process.terminationStatus))"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return outputURL
    }

    /// Creates an AES-256 encrypted tarball (.tar.gz.enc) from the given items.
    func createEncryptedTarball(
        from urls: [URL],
        in destinationDir: URL,
        baseName: String? = nil,
        password: String
    ) async throws -> URL {
        guard !urls.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No items to archive"])
        }
        guard !password.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Password cannot be empty"])
        }

        let archiveBase = baseName ?? (urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Encrypted Archive")
        let fm = FileManager.default
        var outputURL = destinationDir.appendingPathComponent("\(archiveBase).tar.gz.enc")
        var counter = 2
        while fm.fileExists(atPath: outputURL.path) {
            outputURL = destinationDir.appendingPathComponent("\(archiveBase) \(counter).tar.gz.enc")
            counter += 1
        }

        let workingDir = urls[0].deletingLastPathComponent()

        let tarProc = Process()
        tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProc.currentDirectoryURL = workingDir
        var tarArgs = ["-czf", "-"]
        for url in urls {
            if url.deletingLastPathComponent().path == workingDir.path {
                tarArgs.append(url.lastPathComponent)
            } else {
                tarArgs.append(url.path)
            }
        }
        tarProc.arguments = tarArgs

        let sslProc = Process()
        sslProc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        sslProc.arguments = [
            "enc", "-aes-256-cbc", "-salt", "-pbkdf2",
            "-pass", "env:ENC_PASS",
            "-out", outputURL.path
        ]
        sslProc.environment = ["ENC_PASS": password]

        let pipe = Pipe()
        tarProc.standardOutput = pipe
        sslProc.standardInput = pipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try tarProc.run()
                    try sslProc.run()
                    tarProc.waitUntilExit()
                    sslProc.waitUntilExit()

                    if tarProc.terminationStatus == 0 && sslProc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ArchiveService",
                            code: Int(sslProc.terminationStatus != 0 ? sslProc.terminationStatus : tarProc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create encrypted tarball"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return outputURL
    }

    /// Extracts and decrypts an encrypted tarball (.tar.gz.enc) into a clean destination directory.
    @discardableResult
    func extractEncryptedTarball(
        archiveURL: URL,
        destination: URL? = nil,
        password: String
    ) async throws -> URL {
        let parentDir = archiveURL.deletingLastPathComponent()
        var baseName = archiveURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix(".tar.gz") {
            baseName = String(baseName.dropLast(7))
        } else if baseName.hasSuffix(".tgz") {
            baseName = String(baseName.dropLast(4))
        } else if baseName.hasSuffix(".tar") {
            baseName = String(baseName.dropLast(4))
        }

        let targetDir: URL
        if let destination {
            targetDir = destination
        } else {
            let fm = FileManager.default
            var candidate = parentDir.appendingPathComponent(baseName)
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = parentDir.appendingPathComponent("\(baseName) \(counter)")
                counter += 1
            }
            targetDir = candidate
        }

        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let sslDec = Process()
        sslDec.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        sslDec.arguments = [
            "enc", "-d", "-aes-256-cbc", "-salt", "-pbkdf2",
            "-pass", "env:ENC_PASS",
            "-in", archiveURL.path
        ]
        sslDec.environment = ["ENC_PASS": password]

        let tarExtract = Process()
        tarExtract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarExtract.arguments = ["-xzf", "-", "-C", targetDir.path]

        let pipe = Pipe()
        sslDec.standardOutput = pipe
        tarExtract.standardInput = pipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try sslDec.run()
                    try tarExtract.run()
                    sslDec.waitUntilExit()
                    tarExtract.waitUntilExit()

                    if sslDec.terminationStatus == 0 && tarExtract.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "ArchiveService",
                            code: Int(sslDec.terminationStatus != 0 ? sslDec.terminationStatus : tarExtract.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Decryption failed. Please check your password."]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return targetDir
    }
}
