import Foundation
import GRDB

/// A named, colored tag (Prompt 11). Persisted in `tag_item`.
struct TagItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// e.g. "#FF5733"
    var colorHex: String
    var createdAt: Date

    static let databaseTableName = "tag_item"
}

/// Join row: a tag applied to a file (Prompt 11). Persisted in `file_tag`;
/// rows cascade-delete with their tag.
struct FileTag: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: UUID
    /// URL.absoluteString of the tagged file.
    var fileURL: String
    var tagID: UUID
    var appliedAt: Date

    static let databaseTableName = "file_tag"
}
