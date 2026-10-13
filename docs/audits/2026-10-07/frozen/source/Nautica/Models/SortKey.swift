import Foundation

/// Sort attribute for directory listings, shared by the icon and list views.
enum SortKey: String, CaseIterable {
    case name
    case size
    case modificationDate
    case creationDate
    case kind

    var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .modificationDate: return "Date Modified"
        case .creationDate: return "Date Created"
        case .kind: return "Kind"
        }
    }
}
