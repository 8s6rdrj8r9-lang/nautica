import SwiftUI
import AppKit

/// A staging shelf where users can drag & drop files/folders to temporarily hold them
/// while navigating across different tabs, split panes, or directories.
struct DropShelfPanelView: View {
    @Binding var stagedURLs: [URL]
    let currentFolderURL: URL
    let selectedItems: [FileItem]
    var onPerformCopy: ([URL], URL) -> Void
    var onPerformMove: ([URL], URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Drop Shelf", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if !stagedURLs.isEmpty {
                    Text("\(stagedURLs.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                if !stagedURLs.isEmpty {
                    Button(action: { stagedURLs.removeAll() }) {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all staged items")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Drop zone
            VStack(spacing: 6) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

                Text(isTargeted ? "Release to stage items" : "Drag files here to stage")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

                if !selectedItems.isEmpty {
                    Button(action: stageSelection) {
                        Label("Stage Selected (\(selectedItems.count))", systemImage: "plus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .background(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
            )
            .padding(10)
            .dropDestination(for: URL.self) { urls, _ in
                addURLs(urls)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }

            Divider()

            // Staged items list
            if stagedURLs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Shelf is Empty")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Collect files from multiple locations, then drag them out or copy/move them in one step.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(stagedURLs, id: \.self) { url in
                            StagedItemRow(
                                url: url,
                                onRemove: { removeURL(url) }
                            )
                        }
                    }
                    .padding(8)
                }

                Divider()

                // Action footer
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Button(action: copyAllToCurrentFolder) {
                            Label("Copy to Here", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                        .help("Copy all staged items into \(currentFolderURL.lastPathComponent)")

                        Button(action: moveAllToCurrentFolder) {
                            Label("Move to Here", systemImage: "arrow.right.doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                        .help("Move all staged items into \(currentFolderURL.lastPathComponent)")
                    }

                    Text("Destination: \(currentFolderURL.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private func stageSelection() {
        let urls = selectedItems.map(\.url)
        addURLs(urls)
    }

    private func addURLs(_ urls: [URL]) {
        for url in urls {
            if !stagedURLs.contains(url) {
                stagedURLs.append(url)
            }
        }
    }

    private func removeURL(_ url: URL) {
        stagedURLs.removeAll { $0 == url }
    }

    private func copyAllToCurrentFolder() {
        guard !stagedURLs.isEmpty else { return }
        onPerformCopy(stagedURLs, currentFolderURL)
    }

    private func moveAllToCurrentFolder() {
        guard !stagedURLs.isEmpty else { return }
        onPerformMove(stagedURLs, currentFolderURL)
        stagedURLs.removeAll()
    }
}

/// A row in the staged items list.
private struct StagedItemRow: View {
    let url: URL
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let size = fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.4)
            .help("Remove from shelf")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color(NSColor.controlBackgroundColor))
        )
        .onHover { isHovered = $0 }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button("Remove from Shelf", role: .destructive, action: onRemove)
        }
    }

    private var fileSize: Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
