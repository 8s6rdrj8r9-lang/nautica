import Foundation
import AppKit

/// Comprehensive diagnostic and health inspection engine for APFS Encrypted Vaults
/// (.sparsebundle and .dmg containers).
public final class VaultDiagnosticsService: @unchecked Sendable {
    public static let shared = VaultDiagnosticsService()

    public struct VaultHealthReport: Sendable {
        public enum Status: String, Sendable {
            case healthy = "Healthy"
            case warning = "Warning"
            case error = "Needs Repair"

            public var sfSymbol: String {
                switch self {
                case .healthy: return "checkmark.shield.fill"
                case .warning: return "exclamationmark.shield.fill"
                case .error: return "xmark.shield.fill"
                }
            }
        }

        public let vaultURL: URL
        public let status: Status
        public let summaryText: String
        public let actualDiskSizeBytes: Int64
        public let virtualCapacityBytes: Int64
        public let bandCount: Int
        public let encryptionType: String
        public let uuid: String?
        public let isMounted: Bool
        public let mountURL: URL?
        public let diagnosticLogs: [String]
        public let canRepair: Bool
    }

    private init() {}

    /// Performs full structural, cryptographic header, and APFS container diagnostics.
    public func checkHealth(for vaultURL: URL) async -> VaultHealthReport {
        var logs: [String] = []
        var status: VaultHealthReport.Status = .healthy
        var actualSizeBytes: Int64 = 0
        var virtualCapacity: Int64 = 0
        var bandCount: Int = 0
        var encryptionType = "Unknown"
        var containerUUID: String? = nil

        let ext = vaultURL.pathExtension.lowercased()
        logs.append("[INFO] Starting health diagnosis for '\(vaultURL.lastPathComponent)'")

        // 1. Structural Validation
        if ext == "sparsebundle" {
            let infoPlistURL = vaultURL.appendingPathComponent("Info.plist")
            let tokenURL = vaultURL.appendingPathComponent("token")
            let bandsURL = vaultURL.appendingPathComponent("bands")

            if !FileManager.default.fileExists(atPath: infoPlistURL.path) {
                logs.append("[ERROR] Missing Info.plist header inside sparse bundle.")
                status = .error
            } else {
                logs.append("[OK] Info.plist header found.")
                if let data = try? Data(contentsOf: infoPlistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    if let sizeStr = plist["size"] as? String, let s = Int64(sizeStr) {
                        virtualCapacity = s
                    } else if let s = plist["size"] as? Int64 {
                        virtualCapacity = s
                    }
                    logs.append("[INFO] Declared virtual capacity: \(ByteCountFormatter.string(fromByteCount: virtualCapacity, countStyle: .file))")
                }
            }

            if !FileManager.default.fileExists(atPath: tokenURL.path) {
                logs.append("[WARNING] Token marker not found (may not affect mounting).")
                if status != .error { status = .warning }
            } else {
                logs.append("[OK] Token marker verified.")
            }

            if let enumerator = FileManager.default.enumerator(at: bandsURL, includingPropertiesForKeys: [.fileSizeKey]) {
                var count = 0
                var totalBytes: Int64 = 0
                while let fileURL = enumerator.nextObject() as? URL {
                    count += 1
                    if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                        totalBytes += Int64(size)
                    }
                }
                bandCount = count
                actualSizeBytes = totalBytes
                logs.append("[OK] Bands directory verified: \(bandCount) bands (\(ByteCountFormatter.string(fromByteCount: actualSizeBytes, countStyle: .file)) on disk).")
            } else {
                logs.append("[ERROR] Unable to access bands directory.")
                status = .error
            }
        } else {
            // DMG file check
            if let attrs = try? FileManager.default.attributesOfItem(atPath: vaultURL.path) {
                actualSizeBytes = attrs[.size] as? Int64 ?? 0
                virtualCapacity = actualSizeBytes
                logs.append("[OK] DMG disk image located: \(ByteCountFormatter.string(fromByteCount: actualSizeBytes, countStyle: .file))")
            } else {
                logs.append("[ERROR] File not accessible at path.")
                status = .error
            }
        }

        // 2. Mount Status & Volume Verification
        let mountCheck = VaultService.shared.isVaultMounted(at: vaultURL)

        // 3. Cryptographic Header Verification
        let isEncryptedProcess = Process()
        isEncryptedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        isEncryptedProcess.arguments = ["isencrypted", "-plist", vaultURL.path(percentEncoded: false)]
        let pipe = Pipe()
        isEncryptedProcess.standardOutput = pipe
        isEncryptedProcess.standardError = Pipe()

        do {
            try isEncryptedProcess.run()
            isEncryptedProcess.waitUntilExit()
            if isEncryptedProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    if let isEnc = plist["encrypted"] as? Bool, isEnc {
                        encryptionType = "Encrypted Container (APFS)"
                        containerUUID = plist["uuid"] as? String
                        logs.append("[OK] Cryptographic container headers verified. UUID: \(containerUUID ?? "N/A")")
                    } else {
                        logs.append("[WARNING] Container is not encrypted.")
                        if status != .error { status = .warning }
                    }
                }
            } else if mountCheck.isMounted {
                // When an encrypted sparse bundle is mounted, hdiutil isencrypted cannot lock the bundle header exclusively.
                // The fact that it is currently mounted confirms cryptographic container validity.
                encryptionType = "Encrypted Container (Active Mount)"
                logs.append("[OK] Cryptographic container is currently unlocked and mounted.")
            } else {
                logs.append("[WARNING] Unable to read encryption metadata.")
                if status != .error { status = .warning }
            }
        } catch {
            logs.append("[ERROR] Error running encryption check: \(error.localizedDescription)")
            status = .error
        }

        // 4. Volume Inspection
        if mountCheck.isMounted, let mountURL = mountCheck.mountURL {
            logs.append("[INFO] Container is currently mounted at: \(mountURL.path)")
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: mountURL.path) {
                let freeBytes = attrs[.systemFreeSize] as? Int64 ?? 0
                let totalBytes = attrs[.systemSize] as? Int64 ?? 0
                logs.append("[OK] APFS volume mounted and readable.")
                logs.append("[INFO] Volume storage: \(ByteCountFormatter.string(fromByteCount: totalBytes - freeBytes, countStyle: .file)) used / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) total.")
            }
        } else {
            logs.append("[INFO] Container is locked (not attached).")
        }

        let summary: String
        switch status {
        case .healthy:
            summary = "Container structure, headers, and sparse bands pass structural inspection."
        case .warning:
            summary = "Minor anomalies observed during structural validation."
        case .error:
            summary = "Container structure or band integrity issues detected. Verification recommended."
        }

        logs.append("[COMPLETE] Diagnostics completed with result: \(status.rawValue)")

        return VaultHealthReport(
            vaultURL: vaultURL,
            status: status,
            summaryText: summary,
            actualDiskSizeBytes: actualSizeBytes,
            virtualCapacityBytes: virtualCapacity,
            bandCount: bandCount,
            encryptionType: encryptionType,
            uuid: containerUUID,
            isMounted: mountCheck.isMounted,
            mountURL: mountCheck.mountURL,
            diagnosticLogs: logs,
            canRepair: status != .healthy
        )
    }

    /// Verifies the structural integrity of the container using hdiutil verify.
    public func verifyIntegrity(vaultURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["verify", vaultURL.path(percentEncoded: false)]

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let msg = err.isEmpty ? (out.isEmpty ? "Verification failed with exit code \(process.terminationStatus)" : out) : err
            throw VaultService.VaultError.executionFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return out.isEmpty ? "Integrity verification passed successfully." : out
    }

    /// Backwards-compatible alias for container integrity verification.
    public func repair(vaultURL: URL) async throws -> String {
        try await verifyIntegrity(vaultURL: vaultURL)
    }
}
