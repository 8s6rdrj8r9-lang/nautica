import SwiftUI

/// Tab modes for the right-hand Inspector / Utility sidebar.
enum RightSidebarTab: String, CaseIterable, Identifiable {
    case recents = "recents"
    case tree = "tree"
    case info = "info"
    case shelf = "shelf"
    case hex = "hex"
    case actions = "actions"
    case git = "git"
    case media = "media"
    case terminal = "terminal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recents: return "clock"
        case .tree: return "list.bullet.indent"
        case .info: return "info.circle"
        case .shelf: return "tray.and.arrow.down"
        case .hex: return "number.square"
        case .actions: return "wand.and.stars"
        case .git: return "arrow.triangle.branch"
        case .media: return "camera"
        case .terminal: return "terminal"
        }
    }

    var title: String {
        switch self {
        case .recents: return "Recents"
        case .tree: return "Tree"
        case .info: return "Info"
        case .shelf: return "Drop Shelf"
        case .hex: return "Hex"
        case .actions: return "Quick Actions"
        case .git: return "Git"
        case .media: return "Media"
        case .terminal: return "Terminal"
        }
    }

    var tooltip: String {
        switch self {
        case .recents: return "Recently visited folders"
        case .tree: return "Directory tree hierarchy"
        case .info: return "File metadata and preview"
        case .shelf: return "Drag and drop staging shelf"
        case .hex: return "Binary hex inspector and ASCII viewer"
        case .actions: return "Batch utilities and tools"
        case .git: return "Git repository status and commits"
        case .media: return "Media, EXIF & document metadata editor"
        case .terminal: return "Embedded command console"
        }
    }
}
