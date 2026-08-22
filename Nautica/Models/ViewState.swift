import Foundation
import SwiftData

/// SwiftData model for per-folder view persistence.
/// Wiring and migration are implemented in Prompt 12.
@Model
final class FolderViewState {
    @Attribute(.unique) var folderPath: String
    var viewMode: String
    var iconSize: Double
    var sortKey: String
    var sortAscending: Bool
    var showHiddenFiles: Bool
    /// List-view column widths in points, keyed by column identifier.
    var columnWidths: [String: Double]?
    /// Ordered list-view column identifiers.
    var columnOrder: [String]?
    var lastVisited: Date

    init(folderPath: String,
         viewMode: String = "icon",
         iconSize: Double = 64,
         sortKey: String = "name",
         sortAscending: Bool = true,
         showHiddenFiles: Bool = false,
         columnWidths: [String: Double]? = nil,
         columnOrder: [String]? = nil,
         lastVisited: Date = .now) {
        self.folderPath = folderPath
        self.viewMode = viewMode
        self.iconSize = iconSize
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        self.showHiddenFiles = showHiddenFiles
        self.columnWidths = columnWidths
        self.columnOrder = columnOrder
        self.lastVisited = lastVisited
    }
}
