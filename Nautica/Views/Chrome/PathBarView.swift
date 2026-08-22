import AppKit
import SwiftUI

/// Breadcrumb path bar: clickable segments, sibling-folder context menus,
/// and drag-to-Favorites support.
struct PathBarView: View {
    var currentURL: URL
    var onNavigate: (URL) -> Void
    var onAddFavorite: (URL) -> Void
    /// Stubbed until real tabs land in Prompt 8.
    var onOpenInNewTab: ((URL) -> Void)? = nil

    /// Sibling folders per segment path, loaded for the context menus.
    @State private var siblings: [String: [FileItem]] = [:]

    private struct Segment: Identifiable {
        let url: URL
        let name: String
        let showsHomeIcon: Bool
        var id: String { url.path }
    }

    /// One segment per path component; the root "/" itself is not shown.
    private var segments: [Segment] {
        let homePath = FileManager.default.homeURL.path
        var url = URL(fileURLWithPath: "/", isDirectory: true)
        var result: [Segment] = []
        for component in currentURL.pathComponents.dropFirst() {
            url = url.appendingPathComponent(component, isDirectory: true)
            // Under the user's home, the "Users" segment shows a home icon.
            let showsHomeIcon = url.path == "/Users" && currentURL.path.hasPrefix(homePath)
            result.append(Segment(url: url, name: component, showsHomeIcon: showsHomeIcon))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 { separator }
                    segmentButton(for: segment, isActive: index == segments.count - 1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .task(id: currentURL) {
            await loadSiblings()
        }
    }

    private var separator: some View {
        Image(nsImage: NSImage(named: NSImage.goRightTemplateName)!)
            .foregroundStyle(.secondary)
            .imageScale(.small)
    }

    private func segmentButton(for segment: Segment, isActive: Bool) -> some View {
        Button {
            onNavigate(segment.url)
        } label: {
            Group {
                if segment.showsHomeIcon {
                    Image(nsImage: NSImage(named: NSImage.homeTemplateName)!)
                } else {
                    Text(segment.name)
                }
            }
            .fontWeight(isActive ? .semibold : .regular)
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenu(for: segment) }
        .onDrag { NSItemProvider(object: segment.url as NSURL) }
    }

    @ViewBuilder
    private func contextMenu(for segment: Segment) -> some View {
        if let items = siblings[segment.id], !items.isEmpty {
            Menu("Sibling Folders") {
                ForEach(items) { item in
                    Button(item.name) { onNavigate(item.url) }
                }
            }
        }
        Button("Open in New Tab") { onOpenInNewTab?(segment.url) }
            .disabled(onOpenInNewTab == nil)
        Button("Add to Favorites") { onAddFavorite(segment.url) }
    }

    /// Loads the sibling folders of every segment for the context menus.
    private func loadSiblings() async {
        var map: [String: [FileItem]] = [:]
        for segment in segments {
            let parent = segment.url.deletingLastPathComponent()
            let items = (try? await FileSystemService.shared.contentsOfDirectory(
                at: parent,
                includingHidden: false
            )) ?? []
            map[segment.id] = items.filter(\.isDirectory)
        }
        siblings = map
    }
}
