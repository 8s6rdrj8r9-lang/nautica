import SwiftUI

/// Right sidebar panel presenting recently visited folders.
struct RecentsPanelView: View {
    let model: SidebarModel
    var currentURL: URL? = nil
    var onNavigate: (URL) -> Void

    @State private var filterText = ""

    private var filteredRecents: [SidebarItem] {
        if filterText.trimmingCharacters(in: .whitespaces).isEmpty {
            return model.recents
        }
        let term = filterText.lowercased()
        return model.recents.filter {
            $0.name.lowercased().contains(term) || $0.url.path.lowercased().contains(term)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with item count and clear button
            HStack {
                Label("Recent Folders", systemImage: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !model.recents.isEmpty {
                    Button(action: { model.clearRecents() }) {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear recent folder history")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.recents.isEmpty {
                emptyStateView
            } else {
                // Filter field if there are multiple items
                if model.recents.count > 5 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField("Filter recents…", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !filterText.isEmpty {
                            Button(action: { filterText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    Divider()
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredRecents) { item in
                            let isSelected = isCurrentURL(item.url)
                            RecentRowView(
                                item: item,
                                isSelected: isSelected,
                                onNavigate: { onNavigate(item.url) },
                                onRemove: {
                                    if let idx = model.recents.firstIndex(of: item) {
                                        model.recents.remove(at: idx)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func isCurrentURL(_ url: URL) -> Bool {
        guard let currentURL else { return false }
        return currentURL.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Recent Folders")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Folders you browse into will appear here for fast access.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A row item in the Recents right sidebar panel.
private struct RecentRowView: View {
    let item: SidebarItem
    let isSelected: Bool
    let onNavigate: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            SidebarRowView(item: item, isSelected: isSelected)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onNavigate() }
        .contextMenu {
            Button("Open Folder") { onNavigate() }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Remove from Recent", role: .destructive) {
                onRemove()
            }
        }
    }
}
