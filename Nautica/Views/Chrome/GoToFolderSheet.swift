import SwiftUI

/// Native-style "Go to Folder" sheet (⌘⇧G) allowing users to enter a POSIX path
/// with tilde (~) expansion and navigate immediately.
struct GoToFolderSheet: View {
    @Binding var isPresented: Bool
    var currentURL: URL
    var onNavigate: (URL) -> Void

    @State private var pathText: String = ""
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Go to Folder")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Enter a path, e.g. ~/Downloads or /usr/local/bin", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit(submit)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Go") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            pathText = currentURL.path
            isFieldFocused = true
        }
    }

    private func submit() {
        errorMessage = nil
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        let targetURL = URL(fileURLWithPath: expandedPath)

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                onNavigate(targetURL)
                isPresented = false
            } else {
                // If user entered a path to a file, navigate to its enclosing folder
                onNavigate(targetURL.deletingLastPathComponent())
                isPresented = false
            }
        } else {
            errorMessage = "The folder “\(trimmed)” can’t be found."
        }
    }
}
