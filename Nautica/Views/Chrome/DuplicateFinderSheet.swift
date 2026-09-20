import SwiftUI
import AppKit

/// Modal sheet for scanning a directory for duplicate files, previewing matches,
/// applying smart selection rules, and moving selected duplicates to Trash with Undo.
struct DuplicateFinderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetDirectory: URL
    var onTrashFiles: (([URL]) -> Void)? = nil

    @State private var isScanning: Bool = true
    @State private var scanProgress: DuplicateScanProgress? = nil
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var selectedURLs: Set<URL> = []
    @State private var activeRule: DuplicateSelectionRule = .keepOldest
    @State private var showConfirmTrash: Bool = false
    @State private var scanTask: Task<Void, Never>? = nil

    private var totalReclaimableBytes: Int64 {
        duplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
    }

    private var selectedReclaimableBytes: Int64 {
        var bytes: Int64 = 0
        for group in duplicateGroups {
            for file in group.files where selectedURLs.contains(file.url) {
                bytes += file.fileSize
            }
        }
        return bytes
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            // Content Area
            if isScanning {
                scanningView
            } else if duplicateGroups.isEmpty {
                emptyView
            } else {
                resultsView
            }

            Divider()

            // Footer Action Bar
            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 740, maxWidth: 880, minHeight: 460, idealHeight: 560, maxHeight: 720)
        .onAppear {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
        .confirmationDialog(
            "Move \(selectedURLs.count) duplicate items to Trash?",
            isPresented: $showConfirmTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                executeTrashSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected duplicate files will be moved to the macOS Trash. You can undo this action with ⌘Z.")
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Find Duplicates in “\(targetDirectory.lastPathComponent)”")
                    .font(.headline)
                Text(targetDirectory.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(value: scanProgress?.percentComplete ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 320)

            VStack(spacing: 4) {
                Text(scanProgress?.phase.rawValue ?? "Scanning directory...")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let progress = scanProgress {
                    Text("\(progress.filesScanned) of \(progress.totalFilesFound) files analyzed • \(progress.confirmedGroups) duplicate groups found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Cancel") {
                scanTask?.cancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("No Duplicate Files Found")
                .font(.title3)
                .fontWeight(.semibold)

            Text("All files in “\(targetDirectory.lastPathComponent)” have unique contents.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Rule selector toolbar
            HStack(spacing: 12) {
                Text("Smart Selection:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                ForEach([DuplicateSelectionRule.keepOldest, .keepNewest, .deselectAll]) { rule in
                    Button(rule.rawValue) {
                        applyRule(rule)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Text("\(duplicateGroups.count) groups • \(ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)) reclaimable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // List of duplicate groups
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(duplicateGroups) { group in
                        duplicateGroupCard(group: group)
                    }
                }
                .padding(16)
            }
        }
    }

    private func duplicateGroupCard(group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Group Header
            HStack(spacing: 8) {
                Image(systemName: "equal.square.fill")
                    .foregroundStyle(Color.accentColor)

                Text(group.displayReclaimable + " Reclaimable")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("(\(group.files.first?.displaySize ?? "") per file)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("SHA-256: " + group.hash.prefix(12) + "…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // File items
            VStack(spacing: 4) {
                ForEach(group.files) { file in
                    duplicateFileRow(file: file)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func duplicateFileRow(file: DuplicateFileItem) -> some View {
        let isSelected = selectedURLs.contains(file.url)

        return HStack(spacing: 10) {
            Button {
                toggleSelection(file.url)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(file.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(file.dateModified.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if isSelected {
                    Text("Marked for Trash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.red.opacity(0.06) : Color.clear)
        )
    }

    private var footerView: some View {
        HStack {
            if !isScanning && !duplicateGroups.isEmpty {
                HStack(spacing: 6) {
                    Text("\(selectedURLs.count) files selected")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(\(ByteCountFormatter.string(fromByteCount: selectedReclaimableBytes, countStyle: .file)) to reclaim)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if !isScanning && !duplicateGroups.isEmpty {
                Button {
                    showConfirmTrash = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Move Selected to Trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedURLs.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func startScan() {
        scanTask = Task {
            do {
                let groups = try await DuplicateFinderService.shared.scan(directory: targetDirectory) { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }

                await MainActor.run {
                    self.duplicateGroups = groups
                    self.isScanning = false
                    applyRule(.keepOldest)
                }
            } catch is CancellationError {
                // Task was canceled
            } catch {
                await MainActor.run {
                    self.isScanning = false
                }
            }
        }
    }

    private func applyRule(_ rule: DuplicateSelectionRule) {
        activeRule = rule
        selectedURLs = DuplicateFinderService.applyRule(rule, to: duplicateGroups)
    }

    private func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    private func executeTrashSelected() {
        let urlsToTrash = Array(selectedURLs)
        guard !urlsToTrash.isEmpty else { return }

        if let onTrashFiles {
            onTrashFiles(urlsToTrash)
        } else {
            Task {
                _ = await FileOperationService.shared.trashItems(urlsToTrash)
            }
        }
        dismiss()
    }
}
