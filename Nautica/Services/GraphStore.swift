import Foundation
import CryptoKit
import GRDB

/// Graph semantics on Nautica's existing SQLite stack. No folder ownership or UI dependencies.
actor GraphStore {
    static let shared = GraphStore(url: Constants.appSupportURL.appendingPathComponent("Graph.sqlite"))
    let url: URL
    private var queue: DatabaseQueue?
    init(url: URL) { self.url = url }

    func database() throws -> DatabaseQueue {
        if let queue { return queue }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("graph-v1") { db in
            for table in ["objects", "relationships"] {
                try db.execute(sql: "CREATE TABLE \(table) (sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL, recordedAt DOUBLE NOT NULL, payload BLOB NOT NULL)")
                try db.execute(sql: "CREATE INDEX \(table)_history ON \(table)(id, recordedAt, sequence)")
                for operation in ["UPDATE", "DELETE"] {
                    try db.execute(sql: "CREATE TRIGGER \(table)_no_\(operation) BEFORE \(operation) ON \(table) BEGIN SELECT RAISE(ABORT, 'Graph revisions are append-only'); END")
                }
            }
            try db.execute(sql: "CREATE TABLE records (kind TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (kind, id))")
            try db.execute(sql: "CREATE TABLE immutable (kind TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, hash TEXT NOT NULL, PRIMARY KEY (kind, id))")
            for operation in ["UPDATE", "DELETE"] {
                try db.execute(sql: "CREATE TRIGGER immutable_no_\(operation) BEFORE \(operation) ON immutable BEGIN SELECT RAISE(ABORT, 'Frozen records are immutable'); END")
            }
        }
        try migrator.migrate(db)
        queue = db
        return db
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func snapshot(asOf: Date = .now) throws -> GraphSnapshot {
        try database().read { try Self.snapshot(db: $0, asOf: asOf) }
    }
    static func snapshot(db: Database, asOf: Date) throws -> GraphSnapshot {
        func revisions<T: Decodable>(_ table: String, _: T.Type) throws -> [T] {
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM \(table) WHERE sequence IN (SELECT MAX(sequence) FROM \(table) WHERE recordedAt <= ? GROUP BY id) ORDER BY id", arguments: [asOf.timeIntervalSince1970])
            return try rows.map { try JSONDecoder().decode(T.self, from: $0["payload"] as Data) }
        }
        let objects = try revisions("objects", NauticaObject.self).filter { $0.lifecycle != "purged" && $0.type != "tombstone" }
        let validObjectIDs = Set(objects.map(\.id))
        let relationships = try revisions("relationships", NauticaRelationship.self).filter {
            $0.lifecycle != "purged" && validObjectIDs.contains($0.sourceObjectID) && validObjectIDs.contains($0.targetObjectID)
        }
        return GraphSnapshot(objects: objects, relationships: relationships, asOf: asOf)
    }
    static func append<T: Encodable>(_ value: T, id: UUID, table: String, at: Date, db: Database) throws {
        try db.execute(sql: "INSERT INTO \(table)(id, recordedAt, payload) VALUES (?, ?, ?)", arguments: [id.uuidString, at.timeIntervalSince1970, try encode(value)])
    }

    /// Deliberate erasure lifecycle: expunges sensitive payloads and evidence blobs while
    /// preserving verifiable non-sensitive deletion receipts and append-only trigger integrity.
    func purgeObject(id: UUID, reason: String) throws -> DeletionReceipt {
        try database().write { db in
            let current = try Self.snapshot(db: db, asOf: .now)
            guard let target = current.objects.first(where: { $0.id == id }) else {
                throw GraphError.invalid("Object not found or already purged.")
            }

            let receipt = DeletionReceipt(
                id: UUID(),
                targetObjectID: id,
                targetType: target.type,
                redactedName: "[PURGED: \(reason)]",
                deletedAt: .now,
                reason: reason,
                evidenceHash: target.evidenceHash
            )

            // 1. Expunge evidence payload from immutable storage if present
            if let hash = target.evidenceHash {
                try db.execute(sql: "DROP TRIGGER IF EXISTS immutable_no_DELETE")
                try db.execute(sql: "DELETE FROM immutable WHERE kind = 'evidence' AND id = ?", arguments: [hash])
                try db.execute(sql: "CREATE TRIGGER immutable_no_DELETE BEFORE DELETE ON immutable BEGIN SELECT RAISE(ABORT, 'Frozen records are immutable'); END")
            }

            // 2. Append tombstone revision to objects
            let tombstone = NauticaObject(
                id: id,
                type: "tombstone",
                name: "[PURGED: \(reason)]",
                metadata: ["purged": "true", "reason": reason],
                tags: [],
                lifecycle: "purged",
                resourceURL: nil,
                evidenceHash: nil
            )
            try Self.append(tombstone, id: id, table: "objects", at: .now, db: db)

            // 3. Mark connected relationships as purged
            let connectedEdges = current.relationships.filter { $0.sourceObjectID == id || $0.targetObjectID == id }
            for var edge in connectedEdges {
                edge.lifecycle = "purged"
                try Self.append(edge, id: edge.id, table: "relationships", at: .now, db: db)
            }

            // 4. Save deletion receipt
            try Self.putRecord(receipt, kind: "deletion_receipt", id: receipt.id.uuidString, db: db)

            return receipt
        }
    }

    func deletionReceipts() throws -> [DeletionReceipt] {
        try records("deletion_receipt", DeletionReceipt.self).sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Full workspace export for data portability and backups.
    func exportWorkspace() throws -> Data {
        let currentSnapshot = try snapshot()
        let currentViews = try views()
        let currentPins = try pins()
        let receipts = try deletionReceipts()
        let export = GraphWorkspaceExport(
            schemaVersion: 1,
            exportedAt: .now,
            objects: currentSnapshot.objects,
            relationships: currentSnapshot.relationships,
            views: currentViews,
            pins: currentPins,
            deletionReceipts: receipts
        )
        return try Self.encode(export)
    }

    /// Imports a previously exported workspace.
    func importWorkspace(from data: Data) throws {
        let export = try JSONDecoder().decode(GraphWorkspaceExport.self, from: data)
        try database().write { db in
            for object in export.objects {
                try Self.append(object, id: object.id, table: "objects", at: export.exportedAt, db: db)
            }
            for rel in export.relationships {
                try Self.append(rel, id: rel.id, table: "relationships", at: export.exportedAt, db: db)
            }
            for view in export.views {
                try Self.putRecord(view, kind: "view", id: view.id.uuidString, db: db)
            }
            for pin in export.pins {
                try Self.putRecord(pin, kind: "pin", id: pin.id.uuidString, db: db)
            }
            for receipt in export.deletionReceipts {
                try Self.putRecord(receipt, kind: "deletion_receipt", id: receipt.id.uuidString, db: db)
            }
        }
    }

    func saveObject(_ object: NauticaObject, at: Date = .now) throws {
        guard !object.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !object.type.isEmpty else { throw GraphError.invalid("Name and type are required.") }
        try database().write { db in
            if let hash = object.evidenceHash { _ = try Self.immutableData(kind: "evidence", id: hash, db: db) }
            try Self.append(object, id: object.id, table: "objects", at: at, db: db)
        }
    }
    func saveRelationship(_ edge: NauticaRelationship, at: Date = .now) throws {
        guard !edge.type.isEmpty, !edge.provenance.establishedBy.isEmpty, !edge.provenance.source.isEmpty else { throw GraphError.invalid("Relationship type, author, and source are required.") }
        if let confidence = edge.provenance.confidence, !(0...1).contains(confidence) { throw GraphError.invalid("Confidence must be between 0 and 1.") }
        try database().write { db in
            let ids = Set(try Self.snapshot(db: db, asOf: at).objects.map(\.id))
            guard ids.contains(edge.sourceObjectID), ids.contains(edge.targetObjectID) else { throw GraphError.invalid("Both relationship endpoints must exist.") }
            try Self.append(edge, id: edge.id, table: "relationships", at: at, db: db)
        }
    }

    /// Registering the same canonical URL reuses identity. Evidence capture is explicit and versioned.
    func registerFile(_ file: URL, captureEvidence: Bool) throws -> NauticaObject {
        let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
        var object = try snapshot().objects.first { $0.resourceURL == canonical } ?? NauticaObject(type: captureEvidence ? "evidence" : "document", name: canonical.lastPathComponent, resourceURL: canonical)
        if captureEvidence {
            let size = try canonical.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true, (size.fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw GraphError.invalid("Evidence must be a regular file no larger than 32 MB.") }
            let bytes = try Data(contentsOf: canonical)
            guard bytes.count <= 32 * 1024 * 1024 else { throw GraphError.invalid("Evidence exceeds 32 MB.") }
            let hash = Self.hash(bytes)
            try database().write { try Self.insertImmutable(bytes, kind: "evidence", id: hash, db: $0) }
            object.evidenceHash = hash
            object.type = "evidence"
        }
        try saveObject(object)
        return object
    }

    func records<T: Decodable>(_ kind: String, _: T.Type) throws -> [T] {
        try database().read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind = ? ORDER BY id", arguments: [kind]).map { try JSONDecoder().decode(T.self, from: $0) }
        }
    }
    func putRecord<T: Encodable>(_ value: T, kind: String, id: String) throws {
        try database().write { db in try Self.putRecord(value, kind: kind, id: id, db: db) }
    }
    static func putRecord<T: Encodable>(_ value: T, kind: String, id: String, db: Database) throws {
        try db.execute(sql: "INSERT INTO records(kind, id, payload) VALUES (?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET payload = excluded.payload", arguments: [kind, id, try encode(value)])
    }
    func views() throws -> [NauticaView] { try records("view", NauticaView.self).sorted { $0.name < $1.name } }
    func saveView(_ view: NauticaView) throws {
        guard !view.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GraphError.invalid("A View needs a name.") }
        if view.definition.kind == .relationship && view.definition.traversal == nil { throw GraphError.invalid("Select a starting object.") }
        try putRecord(view, kind: "view", id: view.id.uuidString)
    }
    func deleteView(_ id: UUID) throws {
        try database().write { db in
            try db.execute(sql: "DELETE FROM records WHERE kind = 'view' AND id = ?", arguments: [id.uuidString])
            let pins = try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind = 'pin'").map { try JSONDecoder().decode(DockPin.self, from: $0) }
            for pin in pins where pin.targetType == .view && pin.targetID == id.uuidString {
                try db.execute(sql: "DELETE FROM records WHERE kind = 'pin' AND id = ?", arguments: [pin.id.uuidString])
            }
        }
    }
    func pins() throws -> [DockPin] { try records("pin", DockPin.self).sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) } }
    func pin(_ target: DockPin.TargetType, id: String) throws {
        let existing = try pins()
        guard !existing.contains(where: { $0.targetType == target && $0.targetID == id }) else { return }
        switch target {
        case .view: guard try views().contains(where: { $0.id.uuidString == id }) else { throw GraphError.invalid("View no longer exists.") }
        case .object: guard try snapshot().objects.contains(where: { $0.id.uuidString == id }) else { throw GraphError.invalid("Object no longer exists.") }
        case .subsystem: guard SubsystemRegistry.all.contains(where: { $0.id == id }) else { throw GraphError.invalid("Unknown subsystem.") }
        case .action: guard id == "newView" else { throw GraphError.invalid("Unknown action.") }
        }
        let pin = DockPin(targetType: target, targetID: id, position: (existing.map(\.position).max() ?? -1) + 1)
        try putRecord(pin, kind: "pin", id: pin.id.uuidString)
    }
    func removePin(_ id: UUID) throws {
        try database().write { try $0.execute(sql: "DELETE FROM records WHERE kind = 'pin' AND id = ?", arguments: [id.uuidString]) }
    }
    func reorderPins(_ ids: [UUID]) throws {
        let pins = try pins()
        guard Set(ids) == Set(pins.map(\.id)), ids.count == pins.count else { throw GraphError.invalid("Dock changed; reload before reordering.") }
        try database().write { db in
            for (position, id) in ids.enumerated() {
                var pin = pins.first { $0.id == id }!
                pin.position = position
                try Self.putRecord(pin, kind: "pin", id: id.uuidString, db: db)
            }
        }
    }
    static func insertImmutable(_ bytes: Data, kind: String, id: String, db: Database) throws {
        if let row = try Row.fetchOne(db, sql: "SELECT payload, hash FROM immutable WHERE kind = ? AND id = ?", arguments: [kind, id]) {
            let stored: Data = row["payload"]
            guard stored == bytes, row["hash"] as String == hash(bytes) else { throw GraphError.invalid("Immutable record conflict or integrity failure.") }
            return
        }
        try db.execute(sql: "INSERT INTO immutable(kind,id,payload,hash) VALUES (?,?,?,?)", arguments: [kind, id, bytes, hash(bytes)])
    }
    static func immutableData(kind: String, id: String, db: Database) throws -> Data {
        guard let row = try Row.fetchOne(db, sql: "SELECT payload, hash FROM immutable WHERE kind = ? AND id = ?", arguments: [kind, id]) else { throw GraphError.invalid("Missing immutable \(kind) record.") }
        let bytes: Data = row["payload"]
        guard hash(bytes) == row["hash"] as String else { throw GraphError.invalid("Integrity check failed for \(kind).") }
        return bytes
    }
    func immutableData(kind: String, id: String) throws -> Data { try database().read { try Self.immutableData(kind: kind, id: id, db: $0) } }
}
