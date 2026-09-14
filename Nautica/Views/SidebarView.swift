import SwiftUI

/// SwiftUI sidebar with Favorites, Tags, and Recent sections. The directory
/// tree lives in the right-hand inspector (`TreePanelView`).
struct SidebarView: View {
    @State private var model: SidebarModel
    /// All stored tags (Prompt 11); refreshed when the sidebar appears.
    @State private var tags: [TagItem] = []

    @AppStorage(Constants.sidebarWidthKey) private var sidebarWidth: Double = 220
    @AppStorage(Constants.sidebarAutoWidthKey) private var autoWidth = false
    @AppStorage(Constants.sidebarFontSizeKey) private var fontSize: Double = 13
    @AppStorage(Constants.sidebarSpacingKey) private var spacing: Double = 4

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
        .font(.system(size: fontSize))
        .environment(\.defaultMinListRowHeight, 0)
        .navigationSplitViewColumnWidth(min: effectiveWidth, ideal: effectiveWidth, max: effectiveWidth)
        .task {
            tags = (try? await TagService.shared.allTags()) ?? []
        }
    }

    private var effectiveWidth: CGFloat {
        guard autoWidth else { return min(600, max(160, sidebarWidth)) }
        let names = model.favorites.map(\.name) + model.recents.map(\.name) + tags.map(\.name)
        let font = NSFont.systemFont(ofSize: fontSize)
        let longest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Include the folder icon, label gap, and both native list margins.
        return min(600, max(160, ceil(longest) + 72))
    }

    // MARK: - Sections

    private var favoritesSection: some View {
        Section("Favorites") {
            ForEach(model.favorites) { item in
                SidebarRowView(item: item)
                    .modifier(SidebarHoverTint())
                    .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
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
                    .modifier(SidebarHoverTint())
                    .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
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
                        .modifier(SidebarHoverTint())
                        .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                        .onTapGesture { onNavigate(item.url) }
                }
            }
        }
    }
}

/// Tint the full row while keeping the sidebar's native spacing and context menus.
private struct SidebarHoverTint: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onDisappear { isHovered = false }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
    }
}

#Preview {
    SidebarView()
}
