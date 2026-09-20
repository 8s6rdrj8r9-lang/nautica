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

        // Pre-populate default system color tags if table is empty
        try queue.write { db in
            let count = try TagItem.fetchCount(db)
            if count == 0 {
                for color in TagColor.allCases {
                    var item = TagItem(id: UUID(), name: color.name, colorHex: color.colorHex, createdAt: Date())
                    try item.insert(db)
                }
            }
        }

        dbQueue = queue
    }

    /// Toggles a standard macOS color tag on the specified URLs.
    func toggleColorTag(_ color: TagColor, for urls: [URL]) throws {
        for url in urls {
            let values = (try? url.resourceValues(forKeys: [.tagNamesKey])) ?? URLResourceValues()
            var currentTags = values.tagNames ?? []
            let tagString = "\(color.name)\n\(color.rawValue)"

            let hasColor = currentTags.contains { tag in
                let info = FileTagInfo(rawName: tag)
                return info.color == color
            }

            if hasColor {
                currentTags.removeAll { tag in
                    let info = FileTagInfo(rawName: tag)
                    return info.color == color
                }
            } else {
                currentTags.append(tagString)
            }

            try? (url as NSURL).setResourceValue(currentTags as NSArray, forKey: .tagNamesKey)

            if let dbTag = try? database().read({ db in
                try TagItem.filter(Column("name") == color.name).fetchOne(db)
            }) {
                if hasColor {
                    try? removeTag(dbTag.id, from: url)
                } else {
                    try? applyTag(dbTag.id, to: url)
                }
            }
        }
    }

    /// Clears all tags from the specified URLs.
    func clearAllTags(for urls: [URL]) throws {
        for url in urls {
            try? (url as NSURL).setResourceValue([] as NSArray, forKey: .tagNamesKey)
            let key = url.absoluteString
            try? database().write { db in
                _ = try FileTag.filter(Column("fileURL") == key).deleteAll(db)
            }
        }
    }

    /// Sets the complete list of tag names for a URL.
    func setTags(_ tags: [String], for url: URL) throws {
        try? (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
        let key = url.absoluteString
        try? database().write { db in
            _ = try FileTag.filter(Column("fileURL") == key).deleteAll(db)
        }
        for tag in tags {
            let info = FileTagInfo(rawName: tag)
            let dbTag = try? database().write { db -> TagItem in
                if let existing = try TagItem.filter(Column("name") == info.displayName).fetchOne(db) {
                    return existing
                }
                var newItem = TagItem(id: UUID(), name: info.displayName, colorHex: info.color?.colorHex ?? "#007AFF", createdAt: Date())
                try newItem.insert(db)
                return newItem
            }
            if let dbTag {
                try? applyTag(dbTag.id, to: url)
            }
        }
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
        var tagName: String?
        try database().write { db in
            let tag = try TagItem.filter(Column("id") == tagID).fetchOne(db)
            tagName = tag?.name
            let exists = try FileTag
                .filter(Column("fileURL") == key && Column("tagID") == tagID)
                .fetchCount(db) > 0
            if !exists {
                var fileTag = FileTag(id: UUID(), fileURL: key, tagID: tagID, appliedAt: Date())
                try fileTag.insert(db)
            }
        }
        if let tagName {
            syncNativeTag(name: tagName, to: url, adding: true)
        }
    }

    func removeTag(_ tagID: UUID, from url: URL) throws {
        let key = url.absoluteString
        var tagName: String?
        try database().write { db in
            let tag = try TagItem.filter(Column("id") == tagID).fetchOne(db)
            tagName = tag?.name
            _ = try FileTag
                .filter(Column("fileURL") == key && Column("tagID") == tagID)
                .deleteAll(db)
        }
        if let tagName {
            syncNativeTag(name: tagName, to: url, adding: false)
        }
    }

    func tagsForFile(_ url: URL) throws -> [TagItem] {
        var dbTags = try database().read { db in
            try TagItem.fetchAll(db, sql: """
                SELECT tag_item.* FROM tag_item
                JOIN file_tag ON file_tag.tagID = tag_item.id
                WHERE file_tag.fileURL = ?
                ORDER BY tag_item.name
                """, arguments: [url.absoluteString])
        }

        // Merge native macOS extended attribute tags from Finder
        if url.isFileURL,
           let values = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let systemTagNames = values.tagNames {
            let existingNames = Set(dbTags.map(\.name))
            for name in systemTagNames where !existingNames.contains(name) {
                let color = Self.colorForStandardTag(name)
                dbTags.append(TagItem(id: UUID(), name: name, colorHex: color, createdAt: Date()))
            }
        }

        return dbTags
    }

    private func syncNativeTag(name: String, to url: URL, adding: Bool) {
        guard url.isFileURL else { return }
        let targetURL = url
        let values = (try? targetURL.resourceValues(forKeys: [.tagNamesKey])) ?? URLResourceValues()
        var currentTags = values.tagNames ?? []
        if adding {
            if !currentTags.contains(name) {
                currentTags.append(name)
            }
        } else {
            currentTags.removeAll { $0 == name }
        }
        try? (targetURL as NSURL).setResourceValue(currentTags as NSArray, forKey: .tagNamesKey)
    }

    private static func colorForStandardTag(_ name: String) -> String {
        switch name.lowercased() {
        case "red": return "#FF3B30"
        case "orange": return "#FF9500"
        case "yellow": return "#FFCC00"
        case "green": return "#34C759"
        case "blue": return "#007AFF"
        case "purple": return "#AF52DE"
        case "gray", "grey": return "#8E8E93"
        default: return "#007AFF"
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
