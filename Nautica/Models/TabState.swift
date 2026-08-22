import Foundation

/// Per-tab browser state (Prompt 8). Each tab owns its own directory listing,
/// selection, navigation history, and view mode.
@Observable
final class TabState: Identifiable, Hashable {
    let id = UUID()
    var directoryContents: DirectoryContents
    var selectionModel: SelectionModel
    var navigationHistory: NavigationHistory
    var viewMode: ViewMode

    var title: String { directoryContents.url.lastPathComponent }

    init(url: URL) {
        directoryContents = DirectoryContents(url: url)
        selectionModel = SelectionModel()
        navigationHistory = NavigationHistory(currentURL: url)
        // New tabs start in the default view mode from Settings (Prompt 14).
        viewMode = ViewMode(
            rawValue: UserDefaults.standard.string(forKey: Constants.defaultViewModeKey) ?? ""
        ) ?? .icon
    }

    static func == (lhs: TabState, rhs: TabState) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
