import SwiftUI

/// Container for the right sidebar (inspector), offering tabbed access to Recents,
/// the Directory Tree, and File Info.
struct RightSidebarView: View {
    @Binding var selectedTab: RightSidebarTab
    let sidebarModel: SidebarModel
    let selectedItems: [FileItem]
    let currentFolderURL: URL
    let currentFolderItemCount: Int
    var onNavigate: (URL) -> Void
    var onQuickLook: () -> Void
    var onOpenTerminal: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Tab Switcher Header
            Picker("Inspector View", selection: $selectedTab) {
                ForEach(RightSidebarTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                        .help(tab.tooltip)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Active Panel View
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
                    onOpenTerminal: onOpenTerminal
                )
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
