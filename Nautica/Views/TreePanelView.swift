import SwiftUI

/// Folder icon + name used by Favorites, Locations, Recent, and tree rows.
struct SidebarRowView: View {
    let item: SidebarItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 18, height: 18)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(item.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)

            Spacer()

            if isCloudItem {
                Image(systemName: "icloud")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var isCloudItem: Bool {
        let name = item.name.lowercased()
        return name == "desktop" || name == "documents"
    }

    @ViewBuilder
    private var iconView: some View {
        let name = item.name.lowercased()
        let path = item.url.path.lowercased()
        if path == "/applications" || name == "applications" {
            Image(systemName: "app.badge")
        } else if name == "desktop" {
            Image(systemName: "display")
        } else if name == "documents" {
            Image(systemName: "doc")
        } else if name == "downloads" {
            Image(systemName: "arrow.down.circle")
        } else if name == "music" {
            Image(systemName: "music.note")
        } else if name == "pictures" {
            Image(systemName: "photo")
        } else if name == "movies" {
            Image(systemName: "film")
        } else if name == "development" || name == "projects" || name == "developer" {
            Image(systemName: "hammer")
        } else if name == "home" || item.url == FileManager.default.homeURL {
            Image(systemName: "house")
        } else if name == "icloud drive" || name == "icloud" {
            Image(systemName: "icloud")
        } else if path == "/" || name == "macintosh hd" {
            Image(systemName: "internaldrive")
        } else if path == "/volumes" || name == "network" {
            Image(systemName: "network")
        } else if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "folder")
        }
    }
}

/// Right-hand directory tree panel (moved out of the left sidebar). The tree
/// is strictly lazy: only the root loads at first; each node enumerates its
/// children when the user expands it.
struct TreePanelView: View {
    let model: SidebarModel
    var onNavigate: (URL) -> Void

    var body: some View {
        ScrollView {
            if let root = model.treeRoot {
                TreeNodeView(item: root, model: model, onNavigate: onNavigate)
                    .padding(8)
            }
        }
        .task {
            if let root = model.treeRoot, !root.isExpanded {
                model.expand(root)
            }
        }
    }
}

/// Recursive, lazily-loaded directory tree node with a disclosure chevron.
private struct TreeNodeView: View {
    let item: SidebarItem
    let model: SidebarModel
    let onNavigate: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    item.isExpanded ? model.collapse(item) : model.expand(item)
                } label: {
                    Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                SidebarRowView(item: item)
                    .onTapGesture { onNavigate(item.url) }

                if model.isLoading(item) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }
            if item.isExpanded, let children = item.children {
                ForEach(children) { child in
                    TreeNodeView(item: child, model: model, onNavigate: onNavigate)
                        .padding(.leading, 14)
                }
            }
        }
    }
}

#Preview {
    TreePanelView(model: SidebarModel()) { _ in }
}
