import SwiftUI
import AppKit

/// Modal sheet for unlocking and mounting an encrypted File Vault via password or Touch ID.
struct UnlockVaultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let vaultURL: URL
    var onUnlocked: ((URL) -> Void)? = nil

    @State private var password: String = ""
    @State private var isUnlocking: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hasKeychainCredentials: Bool = false
    @State private var canUseBiometrics: Bool = false

    private var vaultName: String {
        vaultURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Unlock Encrypted Vault")
                        .font(.headline)
                    Text(vaultName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(spacing: 16) {
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

                // Touch ID Quick Unlock (if credentials in Keychain)
                if hasKeychainCredentials && canUseBiometrics {
                    Button {
                        unlockWithBiometrics()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "touchid")
                                .font(.system(size: 18))
                            Text("Unlock with Touch ID")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isUnlocking)

                    HStack {
                        VStack { Divider() }
                        Text("or enter password")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        VStack { Divider() }
                    }
                }

                // Password input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passphrase")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    SecureField("Enter vault passphrase", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !password.isEmpty {
                                unlockWithPassword()
                            }
                        }
                }
            }
            .padding(20)

            Divider()

            // Footer Actions
            HStack(spacing: 10) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isUnlocking)

                Spacer()

                Button {
                    unlockWithPassword()
                } label: {
                    HStack(spacing: 6) {
                        if isUnlocking {
                            ProgressView().controlSize(.small)
                        }
                        Text("Unlock")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isUnlocking)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 380)
        .onAppear {
            hasKeychainCredentials = VaultService.shared.hasSavedPasswordInKeychain(for: vaultURL)
            canUseBiometrics = VaultService.shared.canUseBiometrics()
            if hasKeychainCredentials && canUseBiometrics {
                unlockWithBiometrics()
            }
        }
    }

    private func unlockWithBiometrics() {
        isUnlocking = true
        errorMessage = nil

        let url = vaultURL
        Task {
            do {
                let mountURL = try await VaultService.shared.unlockVault(
                    at: url,
                    password: nil,
                    useBiometricsIfAvailable: true
                )

                await MainActor.run {
                    isUnlocking = false
                    dismiss()
                    onUnlocked?(mountURL)
                }
            } catch {
                await MainActor.run {
                    isUnlocking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func unlockWithPassword() {
        guard !password.isEmpty else { return }
        isUnlocking = true
        errorMessage = nil

        let url = vaultURL
        let pass = password

        Task {
            do {
                let mountURL = try await VaultService.shared.unlockVault(
                    at: url,
                    password: pass,
                    useBiometricsIfAvailable: false
                )

                await MainActor.run {
                    isUnlocking = false
                    dismiss()
                    onUnlocked?(mountURL)
                }
            } catch {
                await MainActor.run {
                    isUnlocking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
