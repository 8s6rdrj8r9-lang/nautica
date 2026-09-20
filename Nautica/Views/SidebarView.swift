import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI sidebar with Favorites, Locations, and Tags sections. Recent history
/// and the directory tree live in the right-hand inspector.
struct SidebarView: View {
    @State private var model: SidebarModel
    var selectedURL: URL? = nil
    /// All stored tags (Prompt 11); refreshed when the sidebar appears.
    @State private var tags: [TagItem] = []

    @AppStorage(Constants.sidebarWidthKey) private var sidebarWidth: Double = 220
    @AppStorage(Constants.sidebarAutoWidthKey) private var autoWidth = false
    @AppStorage(Constants.sidebarFontSizeKey) private var fontSize: Double = 13
    @AppStorage(Constants.sidebarSpacingKey) private var spacing: Double = 4
    @Environment(\.openWindow) private var openWindow

    var onNavigate: (URL) -> Void
    var onFavoriteAdded: (URL) -> Void
    var onPerformCopy: (([URL], URL) -> Void)? = nil
    var onPerformMove: (([URL], URL) -> Void)? = nil
    var onTagSelected: ((TagItem) -> Void)? = nil

    init(
        model: SidebarModel,
        selectedURL: URL? = nil,
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in },
        onPerformCopy: (([URL], URL) -> Void)? = nil,
        onPerformMove: (([URL], URL) -> Void)? = nil,
        onTagSelected: ((TagItem) -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.selectedURL = selectedURL
        self.onNavigate = onNavigate
        self.onFavoriteAdded = onFavoriteAdded
        self.onPerformCopy = onPerformCopy
        self.onPerformMove = onPerformMove
        self.onTagSelected = onTagSelected
    }

    init(
        selectedURL: URL? = nil,
        onNavigate: @escaping (URL) -> Void = { _ in },
        onFavoriteAdded: @escaping (URL) -> Void = { _ in },
        onPerformCopy: (([URL], URL) -> Void)? = nil,
        onPerformMove: (([URL], URL) -> Void)? = nil,
        onTagSelected: ((TagItem) -> Void)? = nil
    ) {
        self.init(
            model: SidebarModel(),
            selectedURL: selectedURL,
            onNavigate: onNavigate,
            onFavoriteAdded: onFavoriteAdded,
            onPerformCopy: onPerformCopy,
            onPerformMove: onPerformMove,
            onTagSelected: onTagSelected
        )
    }

    var body: some View {
        List {
            favoritesSection
            cloudStorageSection
            locationsSection
            sharedSection
            tagsSection
        }
        .listStyle(.sidebar)
        .font(.system(size: fontSize))
        .environment(\.defaultMinListRowHeight, 0)
        .navigationSplitViewColumnWidth(min: 170, ideal: effectiveWidth, max: 280)
        .task {
            model.refreshCloudStorage()
            tags = (try? await TagService.shared.allTags()) ?? []
        }
    }

    private var effectiveWidth: CGFloat {
        guard autoWidth else { return min(600, max(160, sidebarWidth)) }
        let names = model.favorites.map(\.name) + model.cloudStorage.map(\.name) + tags.map(\.name)
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
        Section {
            ForEach(model.favorites) { item in
                let isSelected = isCurrentURL(item.url)
                SidebarRowView(item: item, isSelected: isSelected)
                    .modifier(SidebarHoverTint(isSelected: isSelected))
                    .modifier(
                        SidebarFolderDropModifier(
                            targetURL: item.url,
                            isInFavorites: true,
                            onAddToFavorites: { urls in
                                for u in urls {
                                    model.addFavorite(url: u)
                                    onFavoriteAdded(u)
                                }
                            },
                            onPerformCopy: onPerformCopy,
                            onPerformMove: onPerformMove,
                            onSpringLoad: { onNavigate($0) }
                        )
                    )
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
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
            .onInsert(of: [UTType.fileURL.identifier]) { index, providers in
                for provider in providers {
                    provider.loadFileURL { url in
                        guard let url else { return }
                        Task { @MainActor in
                            model.insertFavorite(url: url, at: index)
                            onFavoriteAdded(url)
                        }
                    }
                }
            }
            .onMove { source, destination in
                model.moveFavorites(from: source, to: destination)
            }
        } header: {
            HStack {
                Text("Favorites")
                Spacer()
            }
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                for url in urls {
                    model.addFavorite(url: url)
                    onFavoriteAdded(url)
                }
                return true
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                model.addFavorite(url: url)
                onFavoriteAdded(url)
            }
            return true
        }
    }

    @ViewBuilder
    private var cloudStorageSection: some View {
        Section {
            ForEach(model.cloudStorage) { item in
                let isSelected = isCurrentURL(item.url)
                SidebarRowView(item: item, isSelected: isSelected)
                    .modifier(SidebarHoverTint(isSelected: isSelected))
                    .modifier(SidebarFolderDropModifier(targetURL: item.url, onPerformCopy: onPerformCopy, onPerformMove: onPerformMove))
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
                    .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                    .onTapGesture { onNavigate(item.url) }
                    .contextMenu {
                        Button("Open in New Tab") {
                            TabRestoreQueue.shared.enqueue(item.url)
                            openWindow(id: "browser")
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        Divider()
                        Button("Hide from Sidebar") {
                            model.hideCloudStorageItem(item: item)
                        }
                    }
            }
        } header: {
            HStack {
                Text("Cloud Storage")
                Spacer()
                Button {
                    promptAddCustomCloudFolder()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add Cloud Folder…")
            }
        }
    }

    private func promptAddCustomCloudFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Pin Cloud Folder"
        panel.message = "Select a folder to pin under Cloud Storage in the sidebar."
        if panel.runModal() == .OK, let url = panel.url {
            model.addCustomCloudFolder(url: url)
        }
    }

    @ViewBuilder
    private var locationsSection: some View {
        if !model.locations.isEmpty {
            Section("Locations") {
                ForEach(model.locations) { item in
                    let isSelected = isCurrentURL(item.url)
                    HStack {
                        SidebarRowView(item: item, isSelected: isSelected)
                        if item.isEjectable {
                            Button {
                                try? model.ejectVolume(item: item)
                            } label: {
                                Image(systemName: "eject.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Eject “\(item.name)”")
                        }
                    }
                    .modifier(SidebarHoverTint(isSelected: isSelected))
                    .modifier(SidebarFolderDropModifier(targetURL: item.url, onPerformCopy: onPerformCopy, onPerformMove: onPerformMove))
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
                    .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                    .onTapGesture { onNavigate(item.url) }
                    .contextMenu {
                        if item.isEjectable {
                            Button("Eject “\(item.name)”") {
                                try? model.ejectVolume(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sharedSection: some View {
        if !model.sharedServers.isEmpty {
            Section("Shared") {
                ForEach(model.sharedServers) { item in
                    let isSelected = isCurrentURL(item.url)
                    HStack {
                        SidebarRowView(item: item, isSelected: isSelected)
                        if item.isEjectable {
                            Button {
                                try? model.ejectVolume(item: item)
                            } label: {
                                Image(systemName: "eject.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Disconnect “\(item.name)”")
                        }
                    }
                    .modifier(SidebarHoverTint(isSelected: isSelected))
                    .modifier(SidebarFolderDropModifier(targetURL: item.url, onPerformCopy: onPerformCopy, onPerformMove: onPerformMove))
                    .onDrag { NSItemProvider(object: item.url as NSURL) }
                    .listRowInsets(EdgeInsets(top: spacing, leading: 8, bottom: spacing, trailing: 8))
                    .onTapGesture { onNavigate(item.url) }
                    .contextMenu {
                        if item.isEjectable {
                            Button("Disconnect “\(item.name)”") {
                                try? model.ejectVolume(item: item)
                            }
                        }
                    }
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
                    .onTapGesture {
                        onTagSelected?(tag)
                    }
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
private extension NSItemProvider {
    func loadFileURL(completion: @escaping @Sendable (URL?) -> Void) {
        if canLoadObject(ofClass: URL.self) {
            _ = loadObject(ofClass: URL.self) { object, _ in
                if let url = object as? URL {
                    completion(url)
                    return
                }
                completion(nil)
            }
        } else if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    completion(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    completion(url)
                } else if let string = item as? String, let url = URL(string: string) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
        } else {
            completion(nil)
        }
    }
}

#Preview {
    SidebarView()
}
