import SwiftUI
import AppKit

/// Modal confirmation sheet allowing users to select an overwrite algorithm,
/// review items to be destroyed, read wear-leveling disclaimers, and securely shred files.
struct SecureDeleteConfirmationSheet: View {
    let items: [FileItem]
    var onDismiss: () -> Void
    var onCompletion: () -> Void

    @State private var selectedAlgorithm: ShredAlgorithm = .dodStandard
    @State private var isShredding = false
    @State private var progress = ShredProgress()
    @State private var errorMessage: String? = nil
    @State private var shredTask: Task<Void, Never>? = nil

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + ($1.size ?? 0) }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Securely Delete \(items.count == 1 ? "“\(items[0].name)”" : "\(items.count) Items")?")
                        .font(.headline)

                    Text("This action cannot be undone. Items will be overwritten on disk and permanently unlinked without moving to Trash.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Item summary list
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Target Items (\(items.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("Total Size: \(formattedTotalSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items.prefix(15)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)

                                Text(item.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                if !item.isDirectory {
                                    Text(item.formattedSize)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        if items.count > 15 {
                            Text("… and \(items.count - 15) more items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 110)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Algorithm selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Shredding Method")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("", selection: $selectedAlgorithm) {
                    ForEach(ShredAlgorithm.allCases) { algo in
                        Text("\(algo.title) (\(algo.passes) \(algo.passes == 1 ? "pass" : "passes"))").tag(algo)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isShredding)

                Text(selectedAlgorithm.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // APFS / SSD Hardware Disclaimer
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                Text("SSD / APFS Notice: Flash translation layers (wear leveling) on modern SSDs may retain physical block remnants until TRIM. Cryptographic shredding overwrites logical file data, flushes hardware buffers (F_FULLFSYNC), zeroes extents, and scrambles directory metadata.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Progress Bar / Live Status during shredding
            if isShredding {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(progress.currentItemName.isEmpty ? "Sanitizing data..." : "Shredding “\(progress.currentItemName)”")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        if progress.totalPasses > 0 {
                            Text("Pass \(progress.currentPass)/\(progress.totalPasses)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: progress.fractionalProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(progress.filesProcessed) of \(progress.totalFiles) items")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(Int(progress.fractionalProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Error display
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Footer actions
            HStack {
                Button("Cancel") {
                    shredTask?.cancel()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isShredding {
                    Button("Stop Shredding") {
                        shredTask?.cancel()
                        isShredding = false
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(role: .destructive, action: startShredding) {
                        Label("Secure Delete Permanently", systemImage: "trash.slash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func startShredding() {
        isShredding = true
        errorMessage = nil

        let urls = items.map(\.url)
        let algorithm = selectedAlgorithm

        shredTask = Task {
            do {
                try await SecureFileDeletionService.shared.secureDelete(
                    urls: urls,
                    algorithm: algorithm
                ) { newProgress in
                    Task { @MainActor in
                        self.progress = newProgress
                    }
                }

                await MainActor.run {
                    self.isShredding = false
                    self.onCompletion()
                    self.onDismiss()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isShredding = false
                    self.errorMessage = "Shredding was cancelled."
                }
            } catch {
                await MainActor.run {
                    self.isShredding = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
