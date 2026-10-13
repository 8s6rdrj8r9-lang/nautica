import SwiftUI
import AppKit

/// Interactive dual-pane folder synchronization modal providing side-by-side diff previews,
/// action overrides, and synchronized file transfers.
struct FolderSyncSheet: View {
    @State var leftURL: URL
    @State var rightURL: URL
    var onDismiss: () -> Void
    var onSyncComplete: () -> Void

    @State private var mode: SyncMode = .mirror
    @State private var differences: [SyncItemDifference] = []
    @State private var isAnalyzing: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncProgress: (completed: Int, total: Int, item: String) = (0, 0, "")
    @State private var selectedFilter: DiffFilter = .changesOnly
    @State private var errorMessage: String? = nil

    enum DiffFilter: String, CaseIterable, Identifiable {
        case changesOnly = "Changes Only"
        case all = "All Files"
        case conflicts = "Conflicts"

        var id: String { rawValue }
    }

    private var filteredDifferences: [SyncItemDifference] {
        switch selectedFilter {
        case .all:
            return differences
        case .changesOnly:
            return differences.filter { $0.action != .skip }
        case .conflicts:
            return differences.filter { $0.status == .conflict }
        }
    }

    private var totalToCopy: Int {
        differences.filter { $0.action == .copyToRight || $0.action == .copyToLeft }.count
    }

    private var totalToDelete: Int {
        differences.filter { $0.action == .deleteRight || $0.action == .deleteLeft }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Synchronizer")
                        .font(.headline)
                    Text("Compare, analyze differences, and synchronize files between two directories.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Source & Target directory bar
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left Folder (Source)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(leftURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button(action: swapFolders) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Swap Left and Right folders")
                .disabled(isAnalyzing || isSyncing)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Right Folder (Target)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(rightURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Sync mode selector
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mode:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $mode) {
                        ForEach(SyncMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isAnalyzing || isSyncing)
                    .onChange(of: mode) { _, _ in
                        analyzeDifferences()
                    }

                    Spacer()

                    Button(action: analyzeDifferences) {
                        Label("Re-Analyze", systemImage: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .disabled(isAnalyzing || isSyncing)
                }

                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Filter bar & Diff summary
            HStack {
                Picker("", selection: $selectedFilter) {
                    ForEach(DiffFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 280)

                Spacer()

                if !differences.isEmpty {
                    Text("\(totalToCopy) to copy, \(totalToDelete) to delete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Differences Table
            if isAnalyzing {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                    Text("Scanning directories and comparing file timestamps...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
            } else if differences.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Folders Are Identical")
                        .font(.headline)
                    Text("No file changes, missing items, or conflicts detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredDifferences) { diff in
                            differenceRow(for: diff)
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // In-flight progress
            if isSyncing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(syncProgress.item.isEmpty ? "Synchronizing..." : "Syncing \(syncProgress.item)")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(syncProgress.completed)/\(syncProgress.total)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(
                        value: syncProgress.total > 0 ? Double(syncProgress.completed) / Double(syncProgress.total) : 0
                    )
                    .progressViewStyle(.linear)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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

            Divider()

            // Footer actions
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSyncing)

                Spacer()

                Button("Synchronize Now") {
                    startSync()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isAnalyzing || isSyncing || (totalToCopy == 0 && totalToDelete == 0))
            }
        }
        .padding(20)
        .frame(width: 650, height: 540)
        .onAppear {
            analyzeDifferences()
        }
    }

    @ViewBuilder
    private func differenceRow(for diff: SyncItemDifference) -> some View {
        HStack(spacing: 8) {
            Image(systemName: diff.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 12))
                .foregroundStyle(diff.isDirectory ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(diff.relativePath)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(diff.status.label)
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor(diff.status))
            }

            Spacer()

            // Action tag
            HStack(spacing: 4) {
                Image(systemName: diff.action.icon)
                    .font(.system(size: 10))
                Text(diff.action.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(actionColor(diff.action).opacity(0.12))
            .foregroundStyle(actionColor(diff.action))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func statusColor(_ status: SyncDifferenceStatus) -> Color {
        switch status {
        case .leftOnly, .leftNewer: return .blue
        case .rightOnly, .rightNewer: return .teal
        case .identical: return .secondary
        case .conflict: return .orange
        }
    }

    private func actionColor(_ action: SyncAction) -> Color {
        switch action {
        case .copyToRight, .copyToLeft: return .accentColor
        case .deleteRight, .deleteLeft: return .red
        case .skip: return .secondary
        }
    }

    private func swapFolders() {
        let temp = leftURL
        leftURL = rightURL
        rightURL = temp
        analyzeDifferences()
    }

    private func analyzeDifferences() {
        isAnalyzing = true
        errorMessage = nil

        let left = leftURL
        let right = rightURL
        let currentMode = mode

        Task {
            do {
                let diffs = try await FolderSyncService.shared.compareFolders(
                    leftURL: left,
                    rightURL: right,
                    mode: currentMode
                )
                await MainActor.run {
                    self.differences = diffs
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }

    private func startSync() {
        isSyncing = true
        errorMessage = nil

        let diffs = differences
        let left = leftURL
        let right = rightURL

        Task {
            do {
                _ = try await FolderSyncService.shared.executeSync(
                    differences: diffs,
                    leftBaseURL: left,
                    rightBaseURL: right
                ) { completed, total, item in
                    Task { @MainActor in
                        self.syncProgress = (completed, total, item)
                    }
                }

                await MainActor.run {
                    self.isSyncing = false
                    self.onSyncComplete()
                    self.onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
