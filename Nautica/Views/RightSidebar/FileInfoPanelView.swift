import SwiftUI
import AppKit

/// Right sidebar inspector panel displaying rich metadata and quick actions for selected file(s)
/// or the current directory.
struct FileInfoPanelView: View {
    let selectedItems: [FileItem]
    let currentFolderURL: URL
    let currentFolderItemCount: Int
    var onQuickLook: () -> Void
    var onOpenTerminal: (URL) -> Void

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if selectedItems.count == 1, let item = selectedItems.first {
                    singleItemView(item)
                } else if selectedItems.count > 1 {
                    multiItemView(selectedItems)
                } else {
                    currentFolderView
                }
            }
            .padding(14)
        }
    }

    // MARK: - Single Item View

    @ViewBuilder
    private func singleItemView(_ item: FileItem) -> some View {
        // Thumbnail / Icon Header
        VStack(spacing: 8) {
            if let icon = item.iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            } else {
                Image(systemName: item.isDirectory ? "folder" : "doc")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
            }

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 4)

            if !item.kind.isEmpty {
                Text(item.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        // Quick Action Buttons
        HStack(spacing: 8) {
            Button(action: onQuickLook) {
                Label("Quick Look", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)

            Button(action: {
                NSWorkspace.shared.open(item.url)
            }) {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }

        Divider()

        // Metadata Grid
        metadataSection("Information") {
            if let size = item.size {
                metaRow("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let mod = item.modificationDate {
                metaRow("Modified", Self.dateFormatter.string(from: mod))
            }
            if let created = item.creationDate {
                metaRow("Created", Self.dateFormatter.string(from: created))
            }
            metaRow("Kind", item.kind.isEmpty ? (item.isDirectory ? "Folder" : "File") : item.kind)
        }

        Divider()

        // Location & Path
        metadataSection("Where") {
            VStack(alignment: .leading, spacing: 4) {
                Text(abbreviatedPath(item.url.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.path, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Text("•").foregroundStyle(.tertiary)

                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    if item.isDirectory {
                        Text("•").foregroundStyle(.tertiary)
                        Button("Terminal") {
                            onOpenTerminal(item.url)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Multi-Item View

    @ViewBuilder
    private func multiItemView(_ items: [FileItem]) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("\(items.count) items selected")
                .font(.system(size: 14, weight: .semibold))

            let totalBytes = items.compactMap(\.size).reduce(0, +)
            if totalBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        Divider()

        metadataSection("Selection Summary") {
            metaRow("Total Count", "\(items.count) files/folders")
            let folderCount = items.filter(\.isDirectory).count
            let fileCount = items.count - folderCount
            if folderCount > 0 && fileCount > 0 {
                metaRow("Composition", "\(folderCount) folders, \(fileCount) files")
            }
        }
    }

    // MARK: - Current Folder View

    @ViewBuilder
    private var currentFolderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text(currentFolderURL.lastPathComponent)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Text("\(currentFolderItemCount) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        Divider()

        metadataSection("Folder Details") {
            metaRow("Item Count", "\(currentFolderItemCount) items")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentFolderURL.path),
               let mod = attrs[.modificationDate] as? Date {
                metaRow("Modified", Self.dateFormatter.string(from: mod))
            }
        }

        Divider()

        metadataSection("Where") {
            VStack(alignment: .leading, spacing: 4) {
                Text(abbreviatedPath(currentFolderURL.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentFolderURL.path, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Text("•").foregroundStyle(.tertiary)

                    Button("Open in Terminal") {
                        onOpenTerminal(currentFolderURL)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeURL.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
