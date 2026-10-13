import SwiftUI

/// Modal sheet requesting password and confirmation for encrypted ZIP creation.
struct CompressPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    let itemCount: Int
    var onConfirm: (String) -> Void

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Encrypt Archive")
                        .font(.headline)
                    Text("Enter a password to encrypt \(itemCount == 1 ? "1 item" : "\(itemCount) items") into a secure ZIP.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Password:")
                        .font(.caption)
                        .fontWeight(.medium)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Verify Password:")
                        .font(.caption)
                        .fontWeight(.medium)
                    SecureField("Re-enter password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commit)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Encrypt & Compress") {
                    commit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirmPassword.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 360)
    }

    private func commit() {
        guard !password.isEmpty else {
            errorMessage = "Password cannot be empty."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        onConfirm(password)
        dismiss()
    }
}
