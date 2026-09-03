import SwiftUI

/// Folder icon + name used by Favorites, Recent, and tree rows.
struct SidebarRowView: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.name)
        } icon: {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "folder")
            }
        }
        .contentShape(Rectangle())
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
