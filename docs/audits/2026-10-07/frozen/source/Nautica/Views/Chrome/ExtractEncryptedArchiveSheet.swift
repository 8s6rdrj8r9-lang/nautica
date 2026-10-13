import SwiftUI
import AppKit

/// Modal sheet prompting for password to decrypt and extract an encrypted archive.
struct ExtractEncryptedArchiveSheet: View {
    let archiveURL: URL
    let destinationDir: URL
    var onDismiss: () -> Void
    var onExtractionComplete: (URL) -> Void

    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var isExtracting: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Extract Encrypted Archive")
                        .font(.headline)
                    Text("Enter password to decrypt and unpack “\(archiveURL.lastPathComponent)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Decryption Password")
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
                } else {
                    SecureField("Enter Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if isExtracting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Decrypting archive...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isExtracting)

                Spacer()

                Button("Extract") {
                    performExtraction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || isExtracting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func performExtraction() {
        isExtracting = true
        errorMessage = nil

        let pass = password
        let url = archiveURL
        let dest = destinationDir

        Task {
            do {
                let extractedURL = try await ArchiveService.shared.extractEncryptedTarball(
                    archiveURL: url,
                    destination: dest,
                    password: pass
                )
                await MainActor.run {
                    self.isExtracting = false
                    self.onExtractionComplete(extractedURL)
                    self.onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.isExtracting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
