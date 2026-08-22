import SwiftUI

/// SwiftUI sidebar with Favorites, Tree, Tags, and Recent sections.
struct SidebarView: View {
    @State private var model: SidebarModel
    /// All stored tags (Prompt 11); refreshed when the sidebar appears.
    @State private var tags: [TagItem] = []

    var onNavigate: (URL) -> Void
    var onFavoriteAdded: (URL) -> Void

    init(
        model: SidebarModel,
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.onNavigate = onNavigate
        self.onFavoriteAdded = onFavoriteAdded
    }

    init(
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in }
    ) {
        self.init(model: SidebarModel(), onNavigate: onNavigate, onFavoriteAdded: onFavoriteAdded)
    }

    var body: some View {
        List {
            favoritesSection
            treeSection
            tagsSection
            recentsSection
        }
        .listStyle(.sidebar)
        .task {
            if let root = model.treeRoot, !root.isExpanded {
                model.expand(root)
            }
            tags = (try? await TagService.shared.allTags()) ?? []
        }
    }

    // MARK: - Sections

    private var favoritesSection: some View {
        Section("Favorites") {
            ForEach(model.favorites) { item in
                SidebarRowView(item: item)
                    .onTapGesture { onNavigate(item.url) }
                    .contextMenu {
                        Button("Remove from Favorites", role: .destructive) {
                            if let index = model.favorites.firstIndex(of: item) {
                                model.removeFavorites(at: IndexSet(integer: index))
                            }
                        }
                    }
            }
            .onMove { source, destination in
                model.moveFavorites(from: source, to: destination)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.addFavorite(url: url)
            onFavoriteAdded(url)
            return true
        }
    }

    private var treeSection: some View {
        Section("Tree") {
            if let root = model.treeRoot {
                TreeNodeView(item: root, model: model, onNavigate: onNavigate)
            }
        }
    }

    /// Stored tags with their color dot (Prompt 11). Filtering the file view
    /// by tag is a later seam; for now this is the inventory.
    private var tagsSection: some View {
        Section("Tags") {
            ForEach(tags) { tag in
                Label {
                    Text(tag.name)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color(hex: tag.colorHex) ?? .secondary)
                }
            }
        }
    }

    private var recentsSection: some View {
        Section("Recent") {
            ForEach(model.recents) { item in
                SidebarRowView(item: item)
                    .onTapGesture { onNavigate(item.url) }
            }
        }
    }
}

/// Folder icon + name used by Favorites, Recent, and tree rows.
private struct SidebarRowView: View {
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
    SidebarView()
}
