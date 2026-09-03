import SwiftUI

/// SwiftUI sidebar with Favorites, Tags, and Recent sections. The directory
/// tree lives in the right-hand inspector (`TreePanelView`).
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
            tagsSection
            recentsSection
        }
        .listStyle(.sidebar)
        .task {
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

    /// Stored tags with their color dot (Prompt 11). Hidden while empty.
    @ViewBuilder
    private var tagsSection: some View {
        if !tags.isEmpty {
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
    }

    @ViewBuilder
    private var recentsSection: some View {
        if !model.recents.isEmpty {
            Section("Recent") {
                ForEach(model.recents) { item in
                    SidebarRowView(item: item)
                        .onTapGesture { onNavigate(item.url) }
                }
            }
        }
    }
}

#Preview {
    SidebarView()
}
