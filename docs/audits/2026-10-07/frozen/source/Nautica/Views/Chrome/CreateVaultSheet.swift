import SwiftUI
import AppKit

/// Modal sheet for configuring and creating an encrypted APFS File Vault.
struct CreateVaultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let parentDirectory: URL
    var onCreated: ((URL) -> Void)? = nil

    @State private var vaultName: String = "Personal Vault"
    @State private var selectedSizeGB: Int = 10
    @State private var encryption: VaultService.EncryptionAlgorithm = .aes256
    @State private var format: VaultService.VaultFormat = .sparsebundle
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var storeInKeychain: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    private let sizePresets = [1, 5, 10, 25, 50, 100]

    private var isValid: Bool {
        let name = vaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                formContentView
                    .padding(16)
            }
            Divider()
            footerView
        }
        .frame(width: 440, height: 480)
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("New Encrypted File Vault")
                    .font(.headline)
                Text("Create a secure, hardware-encrypted APFS storage container.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var formContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            nameSection
            capacitySection
            optionsSection
            Divider()
            passwordSection
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vault Name")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Vault Name", text: $vaultName)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Maximum Capacity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedSizeGB) GB")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(sizePresets, id: \.self) { size in
                    if selectedSizeGB == size {
                        Button("\(size) GB") {
                            selectedSizeGB = size
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("\(size) GB") {
                            selectedSizeGB = size
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
            }

            Text("APFS Sparse Bundles only consume actual space as files are added, up to this quota.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Encryption")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $encryption) {
                    ForEach(VaultService.EncryptionAlgorithm.allCases) { enc in
                        Text(enc.rawValue).tag(enc)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Format")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $format) {
                    ForEach(VaultService.VaultFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vault Password")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                SecureField("Choose a strong passphrase", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Password")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                SecureField("Verify passphrase", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords do not match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle("Save in Keychain & allow Touch ID biometric unlock", isOn: $storeInKeychain)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isCreating)

            Spacer()

            Button {
                executeCreate()
            } label: {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    }
                    Text("Create Vault")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isCreating)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func executeCreate() {
        guard isValid else { return }
        isCreating = true
        errorMessage = nil

        let name = vaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeMB = selectedSizeGB * 1024
        let enc = encryption
        let fmt = format
        let pass = password
        let keychain = storeInKeychain
        let parent = parentDirectory

        Task {
            do {
                let createdURL = try await VaultService.shared.createVault(
                    named: name,
                    at: parent,
                    maxSizeMB: sizeMB,
                    encryption: enc,
                    format: fmt,
                    password: pass,
                    storeInKeychain: keychain
                )

                await MainActor.run {
                    isCreating = false
                    dismiss()
                    onCreated?(createdURL)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
