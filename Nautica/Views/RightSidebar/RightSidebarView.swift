import SwiftUI

/// Container for the right sidebar (inspector), offering tabbed access across all 8 panels:
/// Recents, Tree, Info, Drop Shelf, Quick Actions, Git Status, Media & EXIF, and Terminal.
struct RightSidebarView: View {
    @Binding var selectedTab: RightSidebarTab
    @Binding var stagedURLs: [URL]
    let sidebarModel: SidebarModel
    let selectedItems: [FileItem]
    let currentFolderURL: URL
    let currentFolderItemCount: Int
    var onNavigate: (URL) -> Void
    var onQuickLook: () -> Void
    var onOpenTerminal: (URL) -> Void
    var onReloadDirectory: () -> Void
    var onPerformCopy: ([URL], URL) -> Void
    var onPerformMove: ([URL], URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // macOS Inspector Icon Tab Bar
            HStack(spacing: 2) {
                ForEach(RightSidebarTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(selectedTab == tab ? "Selected" : "")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .help("\(tab.title) — \(tab.tooltip)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Active Panel
            switch selectedTab {
            case .recents:
                RecentsPanelView(
                    model: sidebarModel,
                    currentURL: currentFolderURL,
                    onNavigate: onNavigate
                )

            case .tree:
                TreePanelView(
                    model: sidebarModel,
                    onNavigate: onNavigate
                )

            case .info:
                FileInfoPanelView(
                    selectedItems: selectedItems,
                    currentFolderURL: currentFolderURL,
                    currentFolderItemCount: currentFolderItemCount,
                    onQuickLook: onQuickLook,
                    onOpenTerminal: onOpenTerminal,
                    onReloadDirectory: onReloadDirectory,
                    onSelectTab: { tab in selectedTab = tab }
                )

            case .shelf:
                DropShelfPanelView(
                    stagedURLs: $stagedURLs,
                    currentFolderURL: currentFolderURL,
                    selectedItems: selectedItems,
                    onPerformCopy: onPerformCopy,
                    onPerformMove: onPerformMove
                )

            case .hex:
                HexViewerPanelView(
                    selectedItem: selectedItems.first
                )

            case .actions:
                QuickActionsPanelView(
                    selectedItems: selectedItems,
                    currentFolderURL: currentFolderURL,
                    onReloadDirectory: onReloadDirectory,
                    onOpenTerminal: onOpenTerminal
                )

            case .git:
                GitStatusPanelView(
                    currentFolderURL: currentFolderURL,
                    onOpenTerminal: onOpenTerminal
                )

            case .media:
                MediaMetadataPanelView(
                    selectedItem: selectedItems.first,
                    onQuickLook: onQuickLook,
                    onReloadDirectory: onReloadDirectory
                )

            case .terminal:
                MiniTerminalPanelView(
                    currentFolderURL: currentFolderURL,
                    onOpenExternalTerminal: onOpenTerminal
                )
            }
        }
        .frame(minWidth: 230, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
