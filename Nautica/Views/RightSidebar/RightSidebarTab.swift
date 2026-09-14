import SwiftUI

/// Tab modes for the right-hand Inspector / Utility sidebar.
enum RightSidebarTab: String, CaseIterable, Identifiable {
    case recents = "recents"
    case tree = "tree"
    case info = "info"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recents: return "clock"
        case .tree: return "list.bullet.indent"
        case .info: return "info.circle"
        }
    }

    var title: String {
        switch self {
        case .recents: return "Recents"
        case .tree: return "Tree"
        case .info: return "Info"
        }
    }

    var tooltip: String {
        switch self {
        case .recents: return "Recently visited folders"
        case .tree: return "Directory tree hierarchy"
        case .info: return "File metadata and preview"
        }
    }
}
