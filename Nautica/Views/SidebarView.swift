import SwiftUI

/// SwiftUI sidebar with Favorites, Tags, and Recent sections. The directory
/// tree lives in the right-hand inspector (`TreePanelView`).
struct SidebarView: View {
    @State private var model: SidebarModel
    var selectedURL: URL? = nil
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
        selectedURL: URL? = nil,
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.selectedURL = selectedURL
        self.onNavigate = onNavigate
        self.onFavoriteAdded = onFavoriteAdded
    }

    init(
        selectedURL: URL? = nil,
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in }
    ) {
        self.init(model: SidebarModel(), selectedURL: selectedURL, onNavigate: onNavigate, onFavoriteAdded: onFavoriteAdded)
    }

    var body: some View {
        List {
            favoritesSection
            locationsSection
            tagsSection
            recentsSection
        }
        .listStyle(.sidebar)
        .font(.system(size: fontSize))
        .environment(\.defaultMinListRowHeight, 0)
        .navigationSplitViewColumnWidth(min: 170, ideal: effectiveWidth, max: 280)
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

    private func isCurrentURL(_ url: URL) -> Bool {
        guard let selectedURL else { return false }
        return selectedURL.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private var favoritesSection: some View {
        Section("Favorites") {
            ForEach(model.favorites) { item in
                let isSelected = isCurrentURL(item.url)
                SidebarRowView(item: item, isSelected: isSelected)
                    .modifier(SidebarHoverTint(isSelected: isSelected))
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

    @ViewBuilder
    private var locationsSection: some View {
        if !model.locations.isEmpty {
            Section("Locations") {
                ForEach(model.locations) { item in
                    let isSelected = isCurrentURL(item.url)
                    SidebarRowView(item: item, isSelected: isSelected)
                        .modifier(SidebarHoverTint(isSelected: isSelected))
                        .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                        .onTapGesture { onNavigate(item.url) }
                }
            }
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
                    .modifier(SidebarHoverTint(isSelected: false))
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
                    let isSelected = isCurrentURL(item.url)
                    SidebarRowView(item: item, isSelected: isSelected)
                        .modifier(SidebarHoverTint(isSelected: isSelected))
                        .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                        .onTapGesture { onNavigate(item.url) }
                }
            }
        }
    }
}

/// Tint the full row with Finder-style selection or hover while keeping spacing and context menus.
private struct SidebarHoverTint: ViewModifier {
    var isSelected: Bool = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onDisappear { isHovered = false }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
    }
}

#Preview {
    SidebarView()
}
