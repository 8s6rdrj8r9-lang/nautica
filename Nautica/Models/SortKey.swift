import Foundation

/// Sort attribute for directory listings, shared by the icon and list views.
enum SortKey: String, CaseIterable {
    case name
    case size
    case modificationDate
    case creationDate
    case kind
}
