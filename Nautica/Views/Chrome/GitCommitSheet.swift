import SwiftUI
import AppKit

/// Modal sheet for reviewing working tree changes, selecting files to stage,
/// and authoring a Git commit directly inside Nautica.
struct GitCommitSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryRoot: URL
    var onCommitCompleted: (() -> Void)? = nil

    @State private var branchName: String = "HEAD"
    @State private var changedFiles: [(path: String, url: URL, state: GitFileState)] = []
    @State private var selectedPaths: Set<String> = []
    @State private var commitMessage: String = ""
    @State private var isCommitting: Bool = false
    @State private var errorMessage: String? = nil

    private var stagedCount: Int {
        selectedPaths.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.badge.questionmark.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Git Commit: \(repositoryRoot.lastPathComponent)")
                            .font(.headline)

                        Text(branchName)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Text("Stage files and enter a commit message.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Main Content: Changed Files List + Message Editor
            HSplitView {
                // Left: Changed Files List
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Changes (\(changedFiles.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        Button("Select All") {
                            selectedPaths = Set(changedFiles.map(\.path))
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)

                        Button("None") {
                            selectedPaths.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    if changedFiles.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            Text("Working tree clean")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(changedFiles, id: \.path) { item in
                            let isSelected = selectedPaths.contains(item.path)
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { isSelected },
                                    set: { selected in
                                        if selected {
                                            selectedPaths.insert(item.path)
                                        } else {
                                            selectedPaths.remove(item.path)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .controlSize(.small)

                                Text(item.state.rawValue)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(nsColor: item.state.badgeColor))
                                    .frame(width: 16, height: 16)
                                    .background(Color(nsColor: item.state.badgeColor).opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text(item.path)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 300)

                // Right: Commit Message Editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commit Message:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    TextEditor(text: $commitMessage)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .frame(minWidth: 320, idealWidth: 380)
            }

            Divider()

            // Footer
            HStack {
                Text("\(stagedCount) of \(changedFiles.count) files staged")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    executeCommit()
                } label: {
                    if isCommitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Commit (\(stagedCount) files)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(stagedCount == 0 || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 650, idealWidth: 720, maxWidth: 860, minHeight: 440, idealHeight: 520, maxHeight: 650)
        .onAppear {
            loadStatus()
        }
    }

    // MARK: - Operations

    private func loadStatus() {
        branchName = GitService.shared.currentBranch(at: repositoryRoot) ?? "HEAD"
        let statusMap = GitService.shared.statusMap(forDirectory: repositoryRoot)

        var list: [(path: String, url: URL, state: GitFileState)] = []
        let rootPath = repositoryRoot.standardizedFileURL.path

        for (pathOrName, state) in statusMap {
            // Avoid duplicates: only include relative paths or filenames
            if !pathOrName.hasPrefix("/") {
                let fileURL = repositoryRoot.appendingPathComponent(pathOrName)
                list.append((path: pathOrName, url: fileURL, state: state))
            }
        }

        // Sort alphabetically
        list.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        self.changedFiles = list
        self.selectedPaths = Set(list.map(\.path))
    }

    private func executeCommit() {
        isCommitting = true
        errorMessage = nil

        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedURLs = changedFiles.filter { selectedPaths.contains($0.path) }.map(\.url)

        Task {
            do {
                try await GitService.shared.stage(urls: selectedURLs, at: repositoryRoot)
                try await GitService.shared.commit(message: message, at: repositoryRoot)

                await MainActor.run {
                    self.isCommitting = false
                    self.onCommitCompleted?()
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isCommitting = false
                }
            }
        }
    }
}
