import Foundation
import GRDB

/// GRDB-backed tag storage at `~/Library/Application Support/Nautica/Tags.sqlite`
/// (Prompt 11). All access goes through the database queue, so reads and
/// writes are serialized and thread-safe.
actor TagService {
    static let shared = TagService()

    enum TagServiceError: Error {
        case databaseNotSetup
    }

    private var dbQueue: DatabaseQueue?

    /// Creates the database file and tables if they don't exist. Called once
    /// at launch; safe to call again (no-op).
    func setupDatabase() throws {
        guard dbQueue == nil else { return }
        try FileManager.default.createDirectory(
            at: Constants.appSupportURL, withIntermediateDirectories: true
        )
        let url = Constants.appSupportURL.appendingPathComponent("Tags.sqlite")
        let queue = try DatabaseQueue(path: url.path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-tags") { db in
            try db.create(table: TagItem.databaseTableName, ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique()
                t.column("colorHex", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: FileTag.databaseTableName, ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("fileURL", .text).notNull()
                t.column("tagID", .text).notNull()
                    .references(TagItem.databaseTableName, onDelete: .cascade)
                t.column("appliedAt", .datetime).notNull()
                t.uniqueKey(["fileURL", "tagID"])
            }
            try db.create(
                index: "idx_file_tag_url", on: FileTag.databaseTableName,
                columns: ["fileURL"], ifNotExists: true
            )
            try db.create(
                index: "idx_file_tag_tag", on: FileTag.databaseTableName,
                columns: ["tagID"], ifNotExists: true
            )
        }
        try migrator.migrate(queue)
        dbQueue = queue
    }

    @discardableResult
    func createTag(name: String, colorHex: String) throws -> TagItem {
        var tag = TagItem(id: UUID(), name: name, colorHex: colorHex, createdAt: Date())
        try database().write { db in
            try tag.insert(db)
        }
        return tag
    }

    /// Deletes the tag; its `file_tag` rows cascade away.
    func deleteTag(id: UUID) throws {
        try database().write { db in
            _ = try TagItem.filter(Column("id") == id).deleteAll(db)
        }
    }

    /// Applies a tag to a file. Applying twice is a no-op.
    func applyTag(_ tagID: UUID, to url: URL) throws {
        let key = url.absoluteString
        try database().write { db in
            let exists = try FileTag
                .filter(Column("fileURL") == key && Column("tagID") == tagID)
                .fetchCount(db) > 0
            if !exists {
                var fileTag = FileTag(id: UUID(), fileURL: key, tagID: tagID, appliedAt: Date())
                try fileTag.insert(db)
            }
        }
    }

    func removeTag(_ tagID: UUID, from url: URL) throws {
        let key = url.absoluteString
        try database().write { db in
            _ = try FileTag
                .filter(Column("fileURL") == key && Column("tagID") == tagID)
                .deleteAll(db)
        }
    }

    func tagsForFile(_ url: URL) throws -> [TagItem] {
        try database().read { db in
            try TagItem.fetchAll(db, sql: """
                SELECT tag_item.* FROM tag_item
                JOIN file_tag ON file_tag.tagID = tag_item.id
                WHERE file_tag.fileURL = ?
                ORDER BY tag_item.name
                """, arguments: [url.absoluteString])
        }
    }

    func filesWithTag(_ tagID: UUID) throws -> [URL] {
        try database().read { db in
            try FileTag
                .filter(Column("tagID") == tagID)
                .fetchAll(db)
                .compactMap { URL(string: $0.fileURL) }
        }
    }

    func allTags() throws -> [TagItem] {
        try database().read { db in
            try TagItem.order(Column("name")).fetchAll(db)
        }
    }

    private func database() throws -> DatabaseQueue {
        guard let dbQueue else { throw TagServiceError.databaseNotSetup }
        return dbQueue
    }
}
