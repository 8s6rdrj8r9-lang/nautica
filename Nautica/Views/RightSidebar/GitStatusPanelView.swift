import SwiftUI
import AppKit

/// Item representing a changed file in Git.
struct GitFileStatus: Identifiable, Hashable {
    let id = UUID()
    let status: String
    let path: String

    var statusColor: Color {
        switch status.trimmingCharacters(in: .whitespaces) {
        case "M": return .orange
        case "A": return .green
        case "??", "?": return .blue
        case "D": return .red
        case "R": return .purple
        default: return .secondary
        }
    }

    var statusDescription: String {
        switch status.trimmingCharacters(in: .whitespaces) {
        case "M": return "Modified"
        case "A": return "Added"
        case "??", "?": return "Untracked"
        case "D": return "Deleted"
        case "R": return "Renamed"
        default: return status
        }
    }
}

/// Right sidebar panel displaying repository branch, uncommitted files, and recent commit history.
struct GitStatusPanelView: View {
    let currentFolderURL: URL
    var onOpenTerminal: (URL) -> Void

    @State private var isGitRepo = false
    @State private var branchName: String?
    @State private var changedFiles: [GitFileStatus] = []
    @State private var recentCommits: [String] = []
    @State private var isLoading = true
    @State private var repoRootURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Git Repository", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if isGitRepo {
                    Button(action: refreshStatus) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Git status")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Git status…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isGitRepo {
                nonRepoView
            } else {
                repoContentView
            }
        }
        .task(id: currentFolderURL) {
            refreshStatus()
        }
    }

    // MARK: - Subviews

    private var nonRepoView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Not a Git Repository")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("This directory is not tracked by Git.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: initGitRepo) {
                Label("Initialize Git Repo", systemImage: "plus")
            }
            .controlSize(.small)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var repoContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Branch Card
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(branchName ?? "HEAD")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if let repoName = repoRootURL?.lastPathComponent {
                            Text(repoName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if changedFiles.isEmpty {
                        Text("Clean")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    } else {
                        Text("\(changedFiles.count) changed")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Changed Files Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Working Tree Changes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if !changedFiles.isEmpty {
                            Button("Stage All") { stageAll() }
                                .font(.system(size: 10))
                                .buttonStyle(.borderless)
                        }
                    }

                    if changedFiles.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("No uncommitted changes")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(changedFiles) { item in
                                HStack(spacing: 6) {
                                    Text(item.status)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(item.statusColor)
                                        .frame(width: 18, alignment: .center)
                                        .padding(.vertical, 2)
                                        .background(item.statusColor.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))

                                    Text(item.path)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }

                Divider()

                // Recent Commits Section
                if !recentCommits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Commits")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 4) {
                            ForEach(recentCommits, id: \.self) { commit in
                                let parts = commit.split(separator: " ", maxSplits: 1)
                                HStack(alignment: .top, spacing: 6) {
                                    if let hash = parts.first {
                                        Text(String(hash))
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.primary.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    if parts.count > 1 {
                                        Text(String(parts[1]))
                                            .font(.system(size: 11))
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)
                                    }
                                    Spacer()
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    Divider()
                }

                // Quick Actions
                Button(action: { onOpenTerminal(currentFolderURL) }) {
                    Label("Open Git in Terminal", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    // MARK: - Git Operations

    private func refreshStatus() {
        isLoading = true
        let url = currentFolderURL

        Task.detached(priority: .userInitiated) {
            let isInside = Self.runGit(["rev-parse", "--is-inside-work-tree"], at: url).trimmingCharacters(in: .whitespacesAndNewlines) == "true"

            guard isInside else {
                await MainActor.run {
                    self.isGitRepo = false
                    self.isLoading = false
                }
                return
            }

            let root = Self.runGit(["rev-parse", "--show-toplevel"], at: url).trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = Self.runGit(["branch", "--show-current"], at: url).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawStatus = Self.runGit(["status", "--porcelain"], at: url)
            let rawLog = Self.runGit(["log", "--oneline", "-5"], at: url)

            var parsedChanges: [GitFileStatus] = []
            for line in rawStatus.components(separatedBy: .newlines) where line.count >= 3 {
                let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !status.isEmpty && !path.isEmpty {
                    parsedChanges.append(GitFileStatus(status: status, path: path))
                }
            }

            let logCommits = rawLog.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            await MainActor.run {
                self.isGitRepo = true
                self.repoRootURL = root.isEmpty ? nil : URL(fileURLWithPath: root)
                self.branchName = branch.isEmpty ? "HEAD" : branch
                self.changedFiles = parsedChanges
                self.recentCommits = logCommits
                self.isLoading = false
            }
        }
    }

    private func stageAll() {
        let url = currentFolderURL
        Task.detached(priority: .userInitiated) {
            _ = Self.runGit(["add", "-A"], at: url)
            await MainActor.run { refreshStatus() }
        }
    }

    private func initGitRepo() {
        let url = currentFolderURL
        Task.detached(priority: .userInitiated) {
            _ = Self.runGit(["init"], at: url)
            await MainActor.run { refreshStatus() }
        }
    }

    private static func runGit(_ args: [String], at directory: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
