import Foundation
import GRDB

/// Package lifecycle and audit storage; no PAF determinations are implemented in the graph engine.
extension GraphStore {
    func importPAF(archive: URL, manifest: URL? = nil, supplements: [URL] = []) throws -> PAFPackage {
        let (package, original) = try PAFPackageLoader.load(archive: archive, manifestURL: manifest, supplements: supplements)
        try database().write { db in
            try Self.insertImmutable(original, kind: "packageArchive", id: package.archiveHash, db: db)
            // Reimporting the same version preserves its original registration time.
            if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM immutable WHERE kind = 'package' AND id = ?", arguments: [package.id]) == 0 {
                try Self.insertImmutable(Self.encode(package), kind: "package", id: package.id, db: db)
            }
        }
        return try pafPackage(package.id)
    }
    func frozenRecords<T: Decodable>(_ kind: String, _: T.Type) throws -> [T] {
        try database().read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM immutable WHERE kind = ? ORDER BY id", arguments: [kind])
            return try ids.map { try JSONDecoder().decode(T.self, from: Self.immutableData(kind: kind, id: $0, db: db)) }
        }
    }
    func pafPackages() throws -> [PAFPackage] { try frozenRecords("package", PAFPackage.self) }
    func pafPackage(_ id: String) throws -> PAFPackage {
        try JSONDecoder().decode(PAFPackage.self, from: immutableData(kind: "package", id: id))
    }
    func saveAuditDraft(_ draft: AuditDraft) throws {
        _ = try pafPackage(draft.packageID)
        try database().write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM immutable WHERE kind = 'audit' AND id = ?", arguments: [draft.id.uuidString]) == 0 else { throw GraphError.invalid("This audit is frozen. Start a new audit for changed inputs.") }
            try Self.putRecord(draft, kind: "intake", id: draft.id.uuidString, db: db)
        }
    }
    func auditDrafts() throws -> [AuditDraft] { try records("intake", AuditDraft.self) }
    func frozenAudits() throws -> [FrozenAudit] { try frozenRecords("audit", FrozenAudit.self) }

    func reviewProjection(_ draft: AuditDraft) throws -> AuditProjection {
        try database().read { try Self.projection(draft, db: $0) }
    }
    private static func projection(_ draft: AuditDraft, db: Database) throws -> AuditProjection {
        guard !draft.propositions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.objectIDs.isEmpty else { throw GraphError.invalid("Provide propositions, scope, and at least one boundary object.") }
        guard draft.graphAsOf <= Date() else { throw GraphError.invalid("The graph revision date cannot be in the future.") }
        if draft.graphAsOf.timeIntervalSince(draft.auditedDate) > 86400 && draft.limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GraphError.invalid("This graph state is later than the audited date. Explicitly describe historical evidence availability and limitations, or choose the historical graph date.")
        }
        let graph = try snapshot(db: db, asOf: draft.graphAsOf)
        let ids = Set(draft.objectIDs)
        let selected = graph.objects.filter { ids.contains($0.id) }
        guard selected.count == ids.count else { throw GraphError.invalid("Some selected objects did not exist in the graph at this date. Choose recorded historical state or explicitly describe later historical evidence and limitations.") }
        let edgeIDs = Set(draft.relationshipIDs)
        let edges = graph.relationships.filter { edgeIDs.contains($0.id) }
        guard edges.count == edgeIDs.count, edges.allSatisfy({ ids.contains($0.sourceObjectID) && ids.contains($0.targetObjectID) }) else { throw GraphError.invalid("Every selected relationship must exist at the graph date and have both endpoints in the boundary.") }
        let authorized = Set(draft.authorizedEvidenceIDs)
        guard authorized.isSubset(of: ids) else { throw GraphError.invalid("Authorized evidence must be within the boundary.") }
        var evidence: [String: Data] = [:]
        var sanitized: [NauticaObject] = []
        var evidenceBytes = 0
        for var object in selected {
            // Live file paths are not auditor authority and cannot grant filesystem access.
            object.resourceURL = nil
            if authorized.contains(object.id) {
                guard let hash = object.evidenceHash else { throw GraphError.invalid("Capture evidence bytes before authorizing \(object.name).") }
                if evidence[hash] == nil {
                    let bytes = try immutableData(kind: "evidence", id: hash, db: db)
                    evidenceBytes += bytes.count
                    guard evidenceBytes <= PAFPackageLoader.maximumBytes else { throw GraphError.invalid("Projection evidence exceeds 128 MB. Narrow the audit boundary.") }
                    evidence[hash] = bytes
                }
            } else { object.evidenceHash = nil }
            sanitized.append(object)
        }
        return AuditProjection(auditID: draft.id, name: draft.name, packageID: draft.packageID, auditedDate: draft.auditedDate, graphAsOf: draft.graphAsOf, propositions: draft.propositions, scope: draft.scope, exclusions: draft.exclusions, governingCriteria: draft.governingCriteria, evidenceRules: draft.evidenceRules, assurance: draft.assurance, limitations: draft.limitations, ambiguities: draft.ambiguities, externalResearchAuthorized: draft.externalResearchAuthorized, objects: sanitized, relationships: edges, evidence: evidence)
    }

    /// Freezes exactly the reviewed bytes. A changing draft/graph forces another review.
    func freezeAudit(_ draft: AuditDraft, reviewedHash: String, command: String) throws -> FrozenAudit {
        try database().write { db in
            let package = try JSONDecoder().decode(PAFPackage.self, from: Self.immutableData(kind: "package", id: draft.packageID, db: db))
            guard package.ready else { throw GraphError.invalid("Package is incomplete: \(package.blockers.joined(separator: "; "))") }
            guard command == package.manifest.freeze_command else { throw GraphError.invalid("Explicit FREEZE & START AUDIT is required.") }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM immutable WHERE kind = 'audit' AND id = ?", arguments: [draft.id.uuidString]) == 0 else { throw GraphError.invalid("Audit already frozen.") }
            let projection = try Self.projection(draft, db: db)
            let projectionHash = Self.hash(try Self.encode(projection))
            guard projectionHash == reviewedHash else { throw GraphError.invalid("The projection changed after review. Review it again before freezing.") }
            let context = try Self.cleanContext(projection, package: package)
            let frozen = FrozenAudit(id: draft.id, projection: projection, projectionHash: projectionHash, frozenAt: .now, context: context, contextHash: Self.hash(context), executionMode: "manual-clean-context-export")
            try Self.putRecord(draft, kind: "intake", id: draft.id.uuidString, db: db)
            try Self.insertImmutable(Self.encode(frozen), kind: "audit", id: draft.id.uuidString, db: db)
            return frozen
        }
    }

    static func cleanContext(_ projection: AuditProjection, package: PAFPackage) throws -> Data {
        // Never include intake prompts/transcripts, expected regression results, patch notes,
        // sibling audits, the original archive, or arbitrary supplemental author documents.
        var materials: [String: Data] = [:]
        for key in ["start_here", "audit_launch"] {
            if let path = package.manifest.entry_points[key], let data = package.files[path] { materials[path] = data }
        }
        for path in package.manifest.templates.values { materials[path] = package.files[path] }
        for (path, data) in package.files where path.hasPrefix(package.manifest.framework_root) {
            let relative = String(path.dropFirst(package.manifest.framework_root.count))
            if let selected = package.manifest.auditor_files {
                if selected.contains(path) { materials[path] = data }
            } else if (!relative.contains("/") && relative.hasPrefix("AUDIT-") && relative.hasSuffix(".md")) || relative == "SPECIALIST-MODULE-CONTRACT.md" || relative.hasPrefix("templates/") {
                materials[path] = data
            }
        }
        struct Context: Encodable {
            let format = "nautica-clean-audit-context-v1"
            let packageID: String
            let archiveSHA256: String
            let methodologyFiles: [String: Data]
            let projection: AuditProjection
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Context(packageID: package.id, archiveSHA256: package.archiveHash, methodologyFiles: materials, projection: projection))
    }

    func captureAuditResponse(auditID: UUID, report: Data, auditor: String, boundaryDeclaration: String) throws -> FrozenAuditResponse {
        guard !auditor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !boundaryDeclaration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GraphError.invalid("Record the auditor identity and actual context-boundary limitations.") }
        guard report.count <= 32 * 1024 * 1024, let text = String(data: report, encoding: .utf8) else { throw GraphError.invalid("The frozen response must be UTF-8 text no larger than 32 MB.") }
        return try database().write { db in
            let audit = try JSONDecoder().decode(FrozenAudit.self, from: Self.immutableData(kind: "audit", id: auditID.uuidString, db: db))
            let package = try JSONDecoder().decode(PAFPackage.self, from: Self.immutableData(kind: "package", id: audit.projection.packageID, db: db))
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).last == package.manifest.completion_marker else { throw GraphError.invalid("The final line must be exactly AUDITOR RESPONSE FROZEN.") }
            let response = FrozenAuditResponse(auditID: auditID, report: report, reportHash: Self.hash(report), capturedAt: .now, auditor: auditor, contextBoundaryDeclaration: boundaryDeclaration)
            try Self.insertImmutable(Self.encode(response), kind: "response", id: auditID.uuidString, db: db)
            let auditObject = NauticaObject(id: auditID, type: "audit", name: audit.projection.name, metadata: ["packageID": package.id, "projectionHash": audit.projectionHash, "reportHash": response.reportHash, "auditor": auditor, "contextBoundary": boundaryDeclaration])
            let reportObject = NauticaObject(type: "frozenReport", name: "Frozen report: \(audit.projection.name)", metadata: ["auditID": auditID.uuidString, "sha256": response.reportHash])
            let edge = NauticaRelationship(type: "frozenReport", sourceObjectID: auditID, targetObjectID: reportObject.id, provenance: RelationshipProvenance(origin: .auditProduced, establishedBy: auditor, source: "sha256:\(response.reportHash)"))
            for object in [auditObject, reportObject] { try Self.append(object, id: object.id, table: "objects", at: response.capturedAt, db: db) }
            try Self.append(edge, id: edge.id, table: "relationships", at: response.capturedAt, db: db)
            return response
        }
    }
    func indexAuditArtifact(auditID: UUID, request: AuditArtifactRequest) throws -> NauticaObject {
        guard ["finding", "verificationRequirement"].contains(request.type), !request.title.isEmpty, !request.reportExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GraphError.invalid("Choose a finding or verification requirement with its exact supporting report excerpt.") }
        return try database().write { db in
            let response = try JSONDecoder().decode(FrozenAuditResponse.self, from: Self.immutableData(kind: "response", id: auditID.uuidString, db: db))
            guard String(data: response.report, encoding: .utf8)?.contains(request.reportExcerpt) == true else { throw GraphError.invalid("The cited excerpt does not occur in the frozen report.") }
            let object = NauticaObject(type: request.type, name: request.title, metadata: ["reportHash": response.reportHash, "reportExcerpt": request.reportExcerpt, "status": "open"])
            let edge = NauticaRelationship(type: request.type == "finding" ? "producedFinding" : "requiresVerification", sourceObjectID: auditID, targetObjectID: object.id, provenance: RelationshipProvenance(origin: .userDefined, establishedBy: NSUserName(), source: "sha256:\(response.reportHash)", status: "user-indexed report excerpt"))
            try Self.append(object, id: object.id, table: "objects", at: .now, db: db)
            try Self.append(edge, id: edge.id, table: "relationships", at: .now, db: db)
            return object
        }
    }
}

extension GraphStore {
    func exportAuditContext(auditID: UUID, parent: URL) throws -> URL {
        let audit = try JSONDecoder().decode(FrozenAudit.self, from: immutableData(kind: "audit", id: auditID.uuidString))
        guard Self.hash(audit.context) == audit.contextHash, Self.hash(try Self.encode(audit.projection)) == audit.projectionHash else { throw GraphError.invalid("Frozen audit integrity failure.") }
        let directory = parent.appendingPathComponent("Audit-\(auditID.uuidString)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try audit.context.write(to: directory.appendingPathComponent("context.json"), options: .atomic)
            // Human-readable projection uses the same date format as the frozen clean context.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(audit.projection).write(to: directory.appendingPathComponent("projection.json"), options: .atomic)
            let package = try pafPackage(audit.projection.packageID)
            let context = try JSONSerialization.jsonObject(with: audit.context) as? [String: Any]
            let materials = context?["methodologyFiles"] as? [String: String] ?? [:]
            for (path, base64) in materials {
                try PAFPackageLoader.validatePath(path)
                guard let bytes = Data(base64Encoded: base64) else { throw GraphError.invalid("Invalid context material.") }
                let destination = directory.appendingPathComponent("methodology").appendingPathComponent(path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: destination)
            }
            let evidenceDirectory = directory.appendingPathComponent("evidence", isDirectory: true)
            try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
            for (hash, bytes) in audit.projection.evidence {
                guard Self.hash(bytes) == hash else { throw GraphError.invalid("Evidence integrity failure.") }
                try bytes.write(to: evidenceDirectory.appendingPathComponent(hash + ".bin"))
            }
            let instructions = """
            Standalone auditor input for \(audit.projection.name).
            Read methodology/\(package.manifest.entry_points["start_here"] ?? "START-HERE.md") and methodology/\(package.manifest.entry_points["audit_launch"] ?? "AUDIT-LAUNCH-PROMPT.md").
            Read projection.json: audited date, recorded graph date, scope, propositions, governing criteria, provenance, and authorized evidence.
            Evidence bytes are in evidence/<SHA256>.bin. Original evidence names and hashes are in the projection Objects.
            Only the provided projection and methodology are included. The intake discussion is excluded.
            Execute in a new independent session; record any context-isolation limitations when returning the report.
            End the response with the exact standalone line: \(package.manifest.completion_marker)
            Package: \(package.id)
            Original archive SHA256: \(package.archiveHash)
            Canonical stored projection SHA256: \(audit.projectionHash)
            Human-readable projection.json uses ISO-8601 dates; its serialization differs from the canonical stored projection.
            Context SHA256: \(audit.contextHash)
            """
            try Data(instructions.utf8).write(to: directory.appendingPathComponent("READ-ME.txt"))
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
