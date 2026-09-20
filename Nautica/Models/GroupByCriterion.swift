import Foundation

/// Criteria for visually dividing file items into section groups.
enum GroupByCriterion: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case kind = "Kind"
    case dateModified = "Date Modified"
    case dateCreated = "Date Created"
    case size = "Size"
    case tags = "Tags"

    var id: String { rawValue }

    var title: String { rawValue }

    var shortcutKey: String? {
        switch self {
        case .none: return "0"
        case .kind: return "2"
        case .dateModified: return "5"
        case .dateCreated: return "6"
        case .size: return "7"
        case .tags: return "8"
        }
    }
}
