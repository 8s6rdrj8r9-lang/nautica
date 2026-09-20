import Foundation
import Security
import LocalAuthentication
import AppKit

/// Service managing encrypted APFS File Vaults (.sparsebundle, .dmg)
/// with support for secure creation, mounting, locking, Keychain persistence,
/// and Touch ID biometric authentication.
public final class VaultService: @unchecked Sendable {
    public static let shared = VaultService()

    public enum EncryptionAlgorithm: String, CaseIterable, Identifiable, Sendable {
        case aes256 = "AES-256"
        case aes128 = "AES-128"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .aes256: return "AES-256 (Highest Security, Recommended)"
            case .aes128: return "AES-128 (Fast & Secure)"
            }
        }
    }

    public enum VaultFormat: String, CaseIterable, Identifiable, Sendable {
        case sparsebundle = "sparsebundle"
        case dmg = "dmg"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .sparsebundle: return "APFS Sparse Bundle (Dynamic, Expands As Needed)"
            case .dmg: return "Read/Write Disk Image (.dmg)"
            }
        }

        public var typeArg: String {
            switch self {
            case .sparsebundle: return "SPARSEBUNDLE"
            case .dmg: return "UDIF"
            }
        }
    }

    public enum VaultError: LocalizedError {
        case invalidPath
        case alreadyExists(String)
        case executionFailed(String)
        case invalidPassphrase
        case notMounted
        case biometricsFailed
        case noSavedCredentials

        public var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "The vault path is invalid."
            case .alreadyExists(let path):
                return "A file or vault already exists at '\(path)'."
            case .executionFailed(let msg):
                return "Disk image operation failed: \(msg)"
            case .invalidPassphrase:
                return "The entered passphrase was incorrect."
            case .notMounted:
                return "The vault is not currently mounted."
            case .biometricsFailed:
                return "Biometric authentication failed or was cancelled."
            case .noSavedCredentials:
                return "No saved credentials found in Keychain for this vault."
            }
        }
    }

    private init() {}

    // MARK: - Vault Creation

    /// Creates an encrypted APFS File Vault (.sparsebundle or .dmg) with password passed securely via stdin.
    @discardableResult
    public func createVault(
        named name: String,
        at destinationFolder: URL,
        maxSizeMB: Int,
        encryption: EncryptionAlgorithm = .aes256,
        format: VaultFormat = .sparsebundle,
        password: String,
        storeInKeychain: Bool = true
    ) async throws -> URL {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw VaultError.invalidPath }

        let ext = format == .sparsebundle ? "sparsebundle" : "dmg"
        let targetURL = destinationFolder.appendingPathComponent("\(cleanName).\(ext)")

        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw VaultError.alreadyExists(targetURL.lastPathComponent)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")

        let args = [
            "create",
            "-size", "\(maxSizeMB)m",
            "-type", format.typeArg,
            "-fs", "APFS",
            "-encryption", encryption.rawValue,
            "-stdinpass",
            "-volname", cleanName,
            targetURL.path(percentEncoded: false)
        ]

        process.arguments = args
        let stdinPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = errPipe

        try process.run()

        if let data = password.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VaultError.executionFailed(errStr.isEmpty ? "Failed to create encrypted vault" : errStr)
        }

        if storeInKeychain {
            savePasswordToKeychain(password, for: targetURL)
        }

        return targetURL
    }

    // MARK: - Vault Attachment / Unlocking

    /// Unlocks and mounts an encrypted File Vault using the provided password or Keychain / Touch ID.
    @discardableResult
    public func unlockVault(
        at url: URL,
        password: String? = nil,
        useBiometricsIfAvailable: Bool = true
    ) async throws -> URL {
        // If already mounted, return existing mount point
        let mountCheck = isVaultMounted(at: url)
        if mountCheck.isMounted, let mountURL = mountCheck.mountURL {
            return mountURL
        }

        var effectivePassword = password

        if effectivePassword == nil || effectivePassword!.isEmpty {
            if useBiometricsIfAvailable && canUseBiometrics() {
                let reason = "Unlock Encrypted File Vault “\(url.deletingPathExtension().lastPathComponent)”"
                let authenticated = await authenticateWithBiometrics(reason: reason)
                if !authenticated {
                    throw VaultError.biometricsFailed
                }
            }

            if let saved = getPasswordFromKeychain(for: url) {
                effectivePassword = saved
            } else {
                throw VaultError.noSavedCredentials
            }
        }

        guard let pass = effectivePassword, !pass.isEmpty else {
            throw VaultError.invalidPassphrase
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-plist", "-nobrowse", "-stdinpass", url.path(percentEncoded: false)]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let errPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = errPipe

        try process.run()

        if let data = pass.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if errStr.localizedCaseInsensitiveContains("Authentication error") ||
               errStr.localizedCaseInsensitiveContains("passphrase") ||
               errStr.localizedCaseInsensitiveContains("incorrect") {
                throw VaultError.invalidPassphrase
            }
            throw VaultError.executionFailed(errStr.isEmpty ? "Failed to unlock vault" : errStr)
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let plist = try? PropertyListSerialization.propertyList(from: outData, options: [], format: nil) as? [String: Any],
           let entities = plist["system-entities"] as? [[String: Any]] {
            for entity in entities {
                if let mountPoint = entity["mount-point"] as? String {
                    return URL(fileURLWithPath: mountPoint)
                }
            }
        }

        // Fallback: Check mounted volumes matching volume name
        let volName = url.deletingPathExtension().lastPathComponent
        let defaultMount = URL(fileURLWithPath: "/Volumes/\(volName)")
        if FileManager.default.fileExists(atPath: defaultMount.path) {
            return defaultMount
        }

        throw VaultError.executionFailed("Attached but unable to locate mount point")
    }

    // MARK: - Vault Detachment / Locking

    /// Detaches and locks a mounted vault volume cleanly.
    public func lockVault(at url: URL) async throws {
        let mountCheck = isVaultMounted(at: url)
        guard mountCheck.isMounted, let mountURL = mountCheck.mountURL else {
            throw VaultError.notMounted
        }

        // Detach volume via hdiutil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountURL.path(percentEncoded: false), "-force"]
        try? process.run()
        process.waitUntilExit()

        // Fallback to AppKit unmount if still present
        if FileManager.default.fileExists(atPath: mountURL.path) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: mountURL)
        }
    }

    // MARK: - Discovery & Status Queries

    /// Returns true if the file or bundle at URL is an encrypted disk image / sparsebundle.
    public func isVault(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "sparsebundle" || ext == "dmg" || ext == "sparseimage" else {
            return false
        }

        // For sparsebundle, fast bundle structure check
        if ext == "sparsebundle" {
            let infoPlist = url.appendingPathComponent("Info.plist")
            let token = url.appendingPathComponent("token")
            return FileManager.default.fileExists(atPath: infoPlist.path) || FileManager.default.fileExists(atPath: token.path)
        }

        // Fast check via hdiutil isencrypted (determines if encrypted without user interaction)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["isencrypted", "-plist", url.path(percentEncoded: false)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let encrypted = plist["encrypted"] as? Bool {
                return encrypted
            }
        } catch {
            return false
        }

        return false
    }

    /// Checks whether the vault image is currently attached and returns its mounted volume URL if so.
    public func isVaultMounted(at url: URL) -> (isMounted: Bool, mountURL: URL?) {
        let targetPath = url.standardizedFileURL.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let images = plist["images"] as? [[String: Any]] {
                for image in images {
                    if let imagePath = image["image-path"] as? String {
                        let stdImagePath = URL(fileURLWithPath: imagePath).standardizedFileURL.path(percentEncoded: false)
                        if stdImagePath == targetPath || imagePath == targetPath {
                            if let entities = image["system-entities"] as? [[String: Any]] {
                                for entity in entities {
                                    if let mount = entity["mount-point"] as? String {
                                        return (true, URL(fileURLWithPath: mount))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            return (false, nil)
        }

        // Fallback check against /Volumes/<VolName>
        let volName = url.deletingPathExtension().lastPathComponent
        let defaultMount = URL(fileURLWithPath: "/Volumes/\(volName)")
        if FileManager.default.fileExists(atPath: defaultMount.path) {
            return (true, defaultMount)
        }

        return (false, nil)
    }

    /// Returns all currently mounted encrypted vaults with their image URL and mount point URL.
    public func mountedVaults() -> [(url: URL, mountPoint: URL)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var results: [(url: URL, mountPoint: URL)] = []

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let images = plist["images"] as? [[String: Any]] {
                for image in images {
                    guard let imagePath = image["image-path"] as? String else { continue }
                    let imageURL = URL(fileURLWithPath: imagePath)
                    guard isVault(at: imageURL) else { continue }

                    if let entities = image["system-entities"] as? [[String: Any]] {
                        for entity in entities {
                            if let mount = entity["mount-point"] as? String {
                                results.append((imageURL, URL(fileURLWithPath: mount)))
                                break
                            }
                        }
                    }
                }
            }
        } catch {
            return []
        }

        return results
    }

    /// Cleanly unmounts and locks all currently mounted vaults. Returns any failures encountered.
    @discardableResult
    public func lockAllVaults() async -> [URL: Error] {
        let vaults = mountedVaults()
        var failures: [URL: Error] = [:]

        for vault in vaults {
            do {
                try await lockVault(at: vault.url)
            } catch {
                failures[vault.url] = error
            }
        }

        return failures
    }

    // MARK: - Biometrics (Touch ID / LocalAuthentication)

    public func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }

    // MARK: - Keychain Helpers

    private let keychainService = "com.arthur.nautica.vault"

    public func hasSavedPasswordInKeychain(for url: URL) -> Bool {
        getPasswordFromKeychain(for: url) != nil
    }

    public func savePasswordToKeychain(_ password: String, for url: URL) {
        let account = url.standardizedFileURL.path(percentEncoded: false)
        guard let data = password.data(using: .utf8) else { return }

        // Remove any prior entry
        deletePasswordFromKeychain(for: url)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    public func getPasswordFromKeychain(for url: URL) -> String? {
        let account = url.standardizedFileURL.path(percentEncoded: false)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func deletePasswordFromKeychain(for url: URL) {
        let account = url.standardizedFileURL.path(percentEncoded: false)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
