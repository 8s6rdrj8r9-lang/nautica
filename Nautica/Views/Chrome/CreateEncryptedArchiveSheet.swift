import SwiftUI
import AppKit

/// Format choices when creating an encrypted archive.
enum EncryptedArchiveFormat: String, CaseIterable, Identifiable {
    case dmg = "dmg"
    case tarEnc = "tarEnc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dmg:
            return "Encrypted Disk Image (.dmg)"
        case .tarEnc:
            return "Encrypted Tarball (.tar.gz.enc)"
        }
    }

    var icon: String {
        switch self {
        case .dmg: return "opticaldiscdrive"
        case .tarEnc: return "doc.zipper"
        }
    }

    var summary: String {
        switch self {
        case .dmg:
            return "Native Apple UDZO disk image protected by hardware-accelerated AES encryption. Mounts as a virtual volume on macOS."
        case .tarEnc:
            return "Standard tarball encrypted using OpenSSL AES-256-CBC with PBKDF2 key derivation. Cross-platform compatible with standard Unix tools."
        }
    }
}

/// Sheet that allows users to create an encrypted disk image (.dmg) or encrypted tarball (.tar.gz.enc)
/// from the currently selected files.
struct CreateEncryptedArchiveSheet: View {
    let items: [FileItem]
    let destinationDir: URL
    var onDismiss: () -> Void
    var onArchiveCreated: (URL) -> Void

    @State private var format: EncryptedArchiveFormat = .dmg
    @State private var archiveName: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword = false
    @State private var encryption: VaultService.EncryptionAlgorithm = .aes256
    @State private var isCreating = false
    @State private var errorMessage: String? = nil

    private var isValid: Bool {
        !archiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        password == confirmPassword
    }

    private var defaultName: String {
        if items.count == 1 {
            return items[0].name.hasSuffix(".app") ? items[0].name : items[0].url.deletingPathExtension().lastPathComponent
        }
        return "Archive"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New Encrypted Archive")
                        .font(.headline)
                    Text("Create a password-protected archive or disk image from \(items.count) \(items.count == 1 ? "item" : "items").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Format Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Archive Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("", selection: $format) {
                    ForEach(EncryptedArchiveFormat.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCreating)

                Text(format.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            // Name field
            VStack(alignment: .leading, spacing: 6) {
                Text("Archive Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                TextField("Name", text: $archiveName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCreating)
            }

            // Passwords
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Password Protection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Toggle("Show", isOn: $showPassword)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }

                if showPassword {
                    TextField("Enter Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    TextField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }

                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Encryption selection for DMG
            if format == .dmg {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Encryption Standard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Picker("", selection: $encryption) {
                        ForEach(VaultService.EncryptionAlgorithm.allCases) { algo in
                            Text(algo.displayName).tag(algo)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isCreating)
                }
            }

            // Error display
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if isCreating {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(format == .dmg ? "Building encrypted disk image..." : "Compressing and encrypting tarball...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Spacer()

                Button("Create Encrypted Archive") {
                    createArchive()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isCreating)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if archiveName.isEmpty {
                archiveName = defaultName
            }
        }
    }

    private func createArchive() {
        isCreating = true
        errorMessage = nil

        let urls = items.map(\.url)
        let name = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        let dest = destinationDir
        let chosenFormat = format
        let enc = encryption

        Task {
            do {
                let createdURL: URL
                switch chosenFormat {
                case .dmg:
                    createdURL = try await ArchiveService.shared.createEncryptedDiskImage(
                        from: urls,
                        in: dest,
                        baseName: name,
                        password: pass,
                        encryption: enc
                    )
                case .tarEnc:
                    createdURL = try await ArchiveService.shared.createEncryptedTarball(
                        from: urls,
                        in: dest,
                        baseName: name,
                        password: pass
                    )
                }

                await MainActor.run {
                    self.isCreating = false
                    self.onArchiveCreated(createdURL)
                    self.onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.isCreating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
