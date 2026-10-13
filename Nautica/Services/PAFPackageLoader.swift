import Foundation

/// Reads ZIP entries into memory; never extracts paths or executes package code.
/// ZIP64, encryption, links, ambiguous paths and oversized entries are rejected.
enum PAFPackageLoader {
    static let maximumBytes = 128 * 1024 * 1024

    static func load(archive: URL, manifestURL: URL? = nil, supplements: [URL] = []) throws -> (PAFPackage, Data) {
        guard supplements.count <= 32 else { throw GraphError.invalid("At most 32 supplemental files are supported.") }
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximumBytes else { throw GraphError.invalid("Package exceeds 128 MB.") }
        let original = try Data(contentsOf: archive)
        let entries = try zipEntries(original)
        // Work from a private exact copy so a changing source cannot mismatch its recorded hash.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copy = temporary.appendingPathComponent("package.zip")
        try original.write(to: copy)
        var files: [String: Data] = [:]
        let names = entries.map(\.name)
        let roots = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        let prefix = roots.count == 1 && names.allSatisfy { $0.contains("/") } ? roots.first! + "/" : ""
        for entry in entries where !entry.name.hasSuffix("/") {
            let name = String(entry.name.dropFirst(prefix.count))
            guard files[name] == nil else { throw GraphError.invalid("Duplicate package path: \(name)") }
            files[name] = try readEntry(copy, name: entry.name, expectedSize: entry.size)
        }
        var supplementalNames: [String] = []
        if let manifestURL {
            guard files["paf-package.json"] == nil else { throw GraphError.invalid("A sidecar cannot replace the packaged manifest.") }
            files["paf-package.json"] = try boundedRead(manifestURL)
            supplementalNames.append("paf-package.json")
        }
        for url in supplements {
            let name = url.lastPathComponent
            try validatePath(name)
            guard files[name] == nil else { throw GraphError.invalid("Supplement would overwrite \(name).") }
            files[name] = try boundedRead(url)
            supplementalNames.append(name)
        }
        guard files.values.reduce(0, { $0 + $1.count }) <= maximumBytes else { throw GraphError.invalid("Package and supplements exceed 128 MB.") }
        guard let manifestBytes = files["paf-package.json"] else { throw GraphError.invalid("No paf-package.json. Select the supplied sidecar manifest for a legacy kit.") }
        let manifest = try JSONDecoder().decode(PAFManifest.self, from: manifestBytes)
        guard manifest.framework == "PAF", manifest.package_format == 1,
              manifest.interaction_model == "intake-freeze-clean-audit",
              manifest.freeze_command == "FREEZE & START AUDIT",
              manifest.completion_marker == "AUDITOR RESPONSE FROZEN" else { throw GraphError.invalid("Unsupported PAF package contract. The original package has not been modified.") }
        try validatePath(manifest.framework_root)
        var blockers: [String] = []
        for key in ["start_here", "audit_intake", "audit_initiation", "audit_launch"] {
            guard let path = manifest.entry_points[key] else { blockers.append("Missing entry point: \(key)"); continue }
            try validatePath(path)
            if files[path] == nil { blockers.append("Missing entry point file: \(path)") }
        }
        for key in ["audit_input", "evidence_register", "audit_report"] {
            guard let path = manifest.templates[key] else { blockers.append("Missing template: \(key)"); continue }
            try validatePath(path)
            if files[path] == nil { blockers.append("Missing template file: \(path)") }
        }
        for path in manifest.auditor_files ?? [] {
            try validatePath(path)
            guard path.hasPrefix(manifest.framework_root), !path.contains("/regression/"), !path.contains("/validation/"), !path.contains("PATCH"), files[path] != nil else {
                throw GraphError.invalid("Invalid or excluded auditor material: \(path)")
            }
        }
        var notes: [String] = []
        var verified = Set<String>()
        if let sums = files["SHA256SUMS.txt"], let text = String(data: sums, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
                let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard parts.count == 2 else { throw GraphError.invalid("Malformed SHA256SUMS.txt entry.") }
                let hash = String(parts[0]).lowercased()
                let path = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                try validatePath(path)
                guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw GraphError.invalid("Invalid SHA-256 digest.") }
                guard let bytes = files[path] else {
                    if path.hasPrefix("source/") { notes.append("Referenced source archive not included: \(path)"); continue }
                    throw GraphError.invalid("Checksum file references missing material: \(path)")
                }
                guard GraphStore.hash(bytes) == hash else { throw GraphError.invalid("Checksum mismatch: \(path)") }
                verified.insert(path)
            }
        } else { blockers.append("Missing SHA256SUMS.txt; framework integrity cannot be verified.") }
        let frameworkFiles = files.keys.filter { $0.hasPrefix(manifest.framework_root) }
        if frameworkFiles.isEmpty { blockers.append("Framework directory is empty.") }
        for path in frameworkFiles where !verified.contains(path) { blockers.append("Framework file has no verified checksum: \(path)") }
        notes.append("\(verified.count) packaged file checksums verified. Hashes do not authenticate the publisher.")
        if !supplementalNames.isEmpty { notes.append("Imported separate supplements without rewriting or renaming package content: \(supplementalNames.joined(separator: ", ")).") }
        let archiveHash = GraphStore.hash(original)
        let id = GraphStore.hash(try GraphStore.encode(["archive": archiveHash, "files": GraphStore.hash(try GraphStore.encode(files))]))
        return (PAFPackage(id: id, archiveHash: archiveHash, originalFilename: archive.lastPathComponent, manifest: manifest, files: files, importedAt: .now, blockers: blockers, integrityNotes: notes, supplementalNames: supplementalNames), original)
    }

    static func boundedRead(_ url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw GraphError.invalid("File exceeds 32 MB.") }
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1024 * 1024 else { throw GraphError.invalid("File exceeds 32 MB.") }
        return data
    }
    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(where: { $0.asciiValue.map { $0 < 32 } ?? false }),
              !path.contains(where: { "*?[]".contains($0) }),
              !parts.contains(".."), !parts.contains("."),
              !path.contains("//") else { throw GraphError.invalid("Unsafe package path: \(path)") }
    }
    struct Entry { let name: String; let size: Int }
    static func zipEntries(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= bytes.count else { throw GraphError.invalid("Truncated ZIP.") }
            return (0..<count).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        guard bytes.count >= 22 else { throw GraphError.invalid("Invalid ZIP.") }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try number(offset, 4) == 0x06054b50, offset + 22 + (try number(offset + 20, 2)) == bytes.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw GraphError.invalid("Unsupported ZIP volume.") }
        let count = try number(end + 10, 2)
        guard count < 4096, count == (try number(end + 8, 2)) else { throw GraphError.invalid("Too many entries or unsupported ZIP64.") }
        var cursor = try number(end + 16, 4)
        var total = 0
        var names = Set<String>()
        var entries: [Entry] = []
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw GraphError.invalid("Invalid ZIP directory.") }
            let flags = try number(cursor + 8, 2)
            let size = try number(cursor + 24, 4)
            let length = try number(cursor + 28, 2)
            let extra = try number(cursor + 30, 2)
            let comment = try number(cursor + 32, 2)
            let attributes = try number(cursor + 38, 4)
            guard flags & 1 == 0, size <= 32 * 1024 * 1024, cursor + 46 + length + extra + comment <= end else { throw GraphError.invalid("Encrypted, oversized or malformed ZIP entry.") }
            let fileType = (attributes >> 16) & 0o170000
            guard fileType == 0 || fileType == 0o100000 || fileType == 0o040000 else { throw GraphError.invalid("Links and special files are not allowed in packages.") }
            guard let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + length)], encoding: .utf8) else { throw GraphError.invalid("Package filenames must be UTF-8.") }
            try validatePath(name)
            guard names.insert(name).inserted else { throw GraphError.invalid("Duplicate ZIP entry.") }
            total += size
            guard total <= maximumBytes else { throw GraphError.invalid("Expanded package exceeds 128 MB.") }
            entries.append(Entry(name: name, size: size))
            cursor += 46 + length + extra + comment
        }
        return entries
    }
    private static func readEntry(_ archive: URL, name: String, expectedSize: Int) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        var result = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            result.append(chunk)
            if result.count > expectedSize { process.terminate(); process.waitUntilExit(); throw GraphError.invalid("ZIP entry exceeds declared size.") }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, result.count == expectedSize else { throw GraphError.invalid("ZIP entry failed integrity/CRC validation: \(name)") }
        return result
    }
}
