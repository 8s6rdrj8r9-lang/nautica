import SwiftUI
import AppKit

/// Visual unified diff viewer with syntax-highlighted lines (additions green, deletions red, hunks cyan).
struct GitDiffSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetURL: URL
    let repositoryRoot: URL
    var onRefreshNeeded: (() -> Void)? = nil

    @State private var diffText: String = ""
    @State private var isLoading: Bool = true
    @State private var branchName: String = "HEAD"
    @State private var showConfirmDiscard: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Git Diff: \(targetURL.lastPathComponent)")
                            .font(.headline)

                        Text(branchName)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Text(targetURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Diff Body
            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating unified diff…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("No Changes Detected")
                        .font(.headline)
                    Text("The working tree matches HEAD for this file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(diffText.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                            diffLineView(line)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.textBackgroundColor))
            }

            Divider()

            // Footer
            HStack {
                Button("Stage File") {
                    stageFile()
                }
                .controlSize(.small)

                Button("Discard Changes…") {
                    showConfirmDiscard = true
                }
                .controlSize(.small)
                .foregroundStyle(.red)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1000, minHeight: 480, idealHeight: 580, maxHeight: 800)
        .onAppear {
            loadDiff()
        }
        .confirmationDialog(
            "Discard all working tree changes in “\(targetURL.lastPathComponent)”?",
            isPresented: $showConfirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                discardChanges()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Unstaged changes in this file will be permanently reverted.")
        }
    }

    // MARK: - Diff Line Renderer

    @ViewBuilder
    private func diffLineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if line.hasPrefix("+++") || line.hasPrefix("---") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if line.hasPrefix("+") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .background(Color.green.opacity(0.12))
        } else if line.hasPrefix("-") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .background(Color.red.opacity(0.12))
        } else if line.hasPrefix("@@") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .background(Color.accentColor.opacity(0.08))
        } else {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private func loadDiff() {
        isLoading = true
        branchName = GitService.shared.currentBranch(at: repositoryRoot) ?? "HEAD"
        Task {
            let output = (try? await GitService.shared.diff(for: targetURL, at: repositoryRoot)) ?? ""
            await MainActor.run {
                self.diffText = output
                self.isLoading = false
            }
        }
    }

    private func stageFile() {
        Task {
            try? await GitService.shared.stage(urls: [targetURL], at: repositoryRoot)
            await MainActor.run {
                onRefreshNeeded?()
                dismiss()
            }
        }
    }

    private func discardChanges() {
        Task {
            try? await GitService.shared.discardChanges(for: [targetURL], at: repositoryRoot)
            await MainActor.run {
                onRefreshNeeded?()
                dismiss()
            }
        }
    }
}
