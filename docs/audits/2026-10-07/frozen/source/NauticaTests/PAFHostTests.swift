import XCTest
import GRDB
@testable import Nautica

final class PAFHostTests: XCTestCase {
    private var directory: URL!
    private var store: GraphStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GraphStore(url: directory.appendingPathComponent("Graph.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: directory) }

    private func fixture(tampered: Bool = false, missingIntake: Bool = false) throws -> URL {
        let root = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("framework/regression/expected"), withIntermediateDirectories: true)
        let manifest = PAFManifest(framework: "PAF", package_format: 1, framework_version: "test", release: "Synthetic test fixture", interaction_model: "intake-freeze-clean-audit", entry_points: ["start_here": "START-HERE.md", "audit_intake": "AUDIT-INTAKE.md", "audit_initiation": "AUDIT-INITIATION.md", "audit_launch": "AUDIT-LAUNCH.md"], framework_root: "framework/", templates: ["audit_input": "INPUT.md", "evidence_register": "EVIDENCE.csv", "audit_report": "REPORT.md"], freeze_command: "FREEZE & START AUDIT", completion_marker: "AUDITOR RESPONSE FROZEN")
        var files: [String: Data] = ["paf-package.json": try GraphStore.encode(manifest)]
        for name in Array(manifest.entry_points.values) + Array(manifest.templates.values) { files[name] = Data("Test material: \(name)".utf8) }
        files["framework/AUDIT-CORE.md"] = Data("Test methodology".utf8)
        files["framework/regression/expected/secret.txt"] = Data("EXPECTED-ANSWER-SECRET".utf8)
        files["AUDIT-INTAKE.md"] = missingIntake ? nil : Data("INTAKE-PROMPT-SECRET".utf8)
        let sums = files.keys.sorted().map { "\(GraphStore.hash(files[$0]!))  \($0)" }.joined(separator: "\n")
        files["SHA256SUMS.txt"] = Data(sums.utf8)
        if tampered { files["framework/AUDIT-CORE.md"] = Data("Tampered".utf8) }
        for (name, data) in files { try data.write(to: root.appendingPathComponent(name)) }
        let zip = directory.appendingPathComponent(UUID().uuidString + ".zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", zip.path, "."]; process.currentDirectoryURL = root
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    func testPackageChecksumsMissingFilesAndArchiveSafety() async throws {
        let package = try await store.importPAF(archive: fixture())
        XCTAssertTrue(package.ready)
        let again = try await store.importPAF(archive: directory.appendingPathComponent(package.originalFilename))
        XCTAssertEqual(again.id, package.id)
        do { _ = try await store.importPAF(archive: fixture(tampered: true)); XCTFail("Tamper accepted") } catch {}
        let incomplete = try await store.importPAF(archive: fixture(missingIntake: true))
        XCTAssertFalse(incomplete.ready)
        for path in ["../outside", "/absolute", "a/../../b", "a\\b", "a/*", "a//b"] { XCTAssertThrowsError(try PAFPackageLoader.validatePath(path)) }
        XCTAssertThrowsError(try PAFPackageLoader.zipEntries(Data("Not a zip".utf8)))
    }

    func testFreezeBoundaryImmutabilityCleanExportAndReportIndexing() async throws {
        let package = try await store.importPAF(archive: fixture())
        var requirement = NauticaObject(type: "requirement", name: "R-17", metadata: ["criterion": "A record must exist"])
        let unrelated = NauticaObject(type: "document", name: "UNRELATED-CONTEXT-SECRET")
        try await store.saveObject(requirement); try await store.saveObject(unrelated)
        let file = directory.appendingPathComponent("evidence.txt")
        try Data("Frozen evidence record".utf8).write(to: file)
        let evidence = try await store.registerFile(file, captureEvidence: true)
        let edge = NauticaRelationship(type: "supportsRequirement", sourceObjectID: evidence.id, targetObjectID: requirement.id, provenance: .init(establishedBy: "tester", source: "record E-22"))
        try await store.saveRelationship(edge)
        var draft = AuditDraft(packageID: package.id, name: "Synthetic host lifecycle test", propositions: "Is the record supplied?", scope: "R-17 only", objectIDs: [requirement.id, evidence.id], relationshipIDs: [edge.id], authorizedEvidenceIDs: [evidence.id], intakeTranscript: "INTAKE-TRANSCRIPT-SECRET")
        try await store.saveAuditDraft(draft)
        let projection = try await store.reviewProjection(draft)
        XCTAssertEqual(projection.objects.count, 2)
        XCTAssertEqual(projection.relationships, [edge])
        XCTAssertTrue(projection.objects.allSatisfy { $0.resourceURL == nil })
        let hash = GraphStore.hash(try GraphStore.encode(projection))
        var changed = draft; changed.propositions = "Changed proposition"
        do { _ = try await store.freezeAudit(changed, reviewedHash: hash, command: "FREEZE & START AUDIT"); XCTFail("Stale review accepted") } catch {}
        do { _ = try await store.freezeAudit(draft, reviewedHash: hash, command: "start"); XCTFail("Missing freeze authorization") } catch {}
        let audit = try await store.freezeAudit(draft, reviewedHash: hash, command: "FREEZE & START AUDIT")
        let context = String(data: audit.context, encoding: .utf8)!
        XCTAssertFalse(context.contains("INTAKE-TRANSCRIPT-SECRET"))
        XCTAssertFalse(context.contains("UNRELATED-CONTEXT-SECRET"))
        XCTAssertFalse(context.contains(Data("EXPECTED-ANSWER-SECRET".utf8).base64EncodedString()))
        XCTAssertFalse(context.contains(Data("INTAKE-PROMPT-SECRET".utf8).base64EncodedString()))
        requirement.name = "Later requirement"
        try await store.saveObject(requirement)
        try Data("Later evidence".utf8).write(to: file)
        _ = try await store.registerFile(file, captureEvidence: true)
        let reopened = GraphStore(url: directory.appendingPathComponent("Graph.sqlite"))
        let savedAudits = try await reopened.frozenAudits()
        XCTAssertEqual(savedAudits.first?.projection, projection)
        XCTAssertEqual(savedAudits.first?.contextHash, audit.contextHash)
        do { try await store.saveAuditDraft(draft); XCTFail("Frozen draft edited") } catch {}
        let db = try await store.database()
        do { try await db.write { try $0.execute(sql: "UPDATE immutable SET hash = 'tamper'") }; XCTFail("Frozen storage was modified") } catch {}
        let exported = try await store.exportAuditContext(auditID: audit.id, parent: directory)
        let exportedContext = try Data(contentsOf: exported.appendingPathComponent("context.json"))
        XCTAssertEqual(exportedContext, audit.context)
        let exportedEvidence = try Data(contentsOf: exported.appendingPathComponent("evidence/\(evidence.evidenceHash!).bin"))
        XCTAssertEqual(String(data: exportedEvidence, encoding: .utf8), "Frozen evidence record")
        do { _ = try await store.captureAuditResponse(auditID: audit.id, report: Data("unfinished".utf8), auditor: "synthetic", boundaryDeclaration: "unit test"); XCTFail("Incomplete response accepted") } catch {}
        let report = Data("SYNTHETIC TEST RESPONSE — not an independent audit.\nFinding F-4: Example finding.\nAUDITOR RESPONSE FROZEN\n".utf8)
        let response = try await store.captureAuditResponse(auditID: audit.id, report: report, auditor: "Synthetic unit-test fixture", boundaryDeclaration: "No model invoked; exercises host lifecycle only")
        XCTAssertEqual(response.report, report)
        let artifact = try await store.indexAuditArtifact(auditID: audit.id, request: .init(type: "finding", title: "F-4", reportExcerpt: "Finding F-4: Example finding."))
        let graph = try await store.snapshot()
        XCTAssertTrue(graph.relationships.contains { $0.type == "producedFinding" && $0.targetObjectID == artifact.id })
        XCTAssertEqual(graph.objects.filter { $0.type == "audit" }.count, 1)
        do { _ = try await store.indexAuditArtifact(auditID: audit.id, request: .init(type: "finding", title: "Invented", reportExcerpt: "Unsupported finding")); XCTFail("Unsupported report semantics accepted") } catch {}
        do { _ = try await store.captureAuditResponse(auditID: audit.id, report: report, auditor: "replacement", boundaryDeclaration: "changed"); XCTFail("Frozen report replaced") } catch {}
        draft.graphAsOf = Date(timeIntervalSince1970: 0)
        do { _ = try await store.reviewProjection(draft); XCTFail("Current state substituted for absent history") } catch {}
    }

    func testUnselectedEdgesAndUnauthorizedEvidenceExcluded() async throws {
        let package = try await store.importPAF(archive: fixture())
        let file = directory.appendingPathComponent("private.txt")
        try Data("NOT-AUTHORIZED".utf8).write(to: file)
        let evidence = try await store.registerFile(file, captureEvidence: true)
        var draft = AuditDraft(packageID: package.id, propositions: "Review metadata", scope: "Metadata only", objectIDs: [evidence.id])
        let projection = try await store.reviewProjection(draft)
        XCTAssertTrue(projection.evidence.isEmpty)
        XCTAssertNil(projection.objects.first?.evidenceHash)
        draft.relationshipIDs = [UUID()]
        do { _ = try await store.reviewProjection(draft); XCTFail("Missing relationship accepted") } catch {}
    }

    /// Optional local integration check. Never imports the private kit into the repository.
    func testUserSuppliedInteractivePackage() async throws {
        let path = ProcessInfo.processInfo.environment["NAUTICA_PAF_PACKAGE"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/PAF-v0.1-Auditor-Kit-Interactive-v1.1.zip").path
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Set NAUTICA_PAF_PACKAGE to run the real-package integration check.") }
        let url = URL(fileURLWithPath: path)
        let package = try await store.importPAF(archive: url)
        XCTAssertTrue(package.ready, package.blockers.joined(separator: "\n"))
        XCTAssertEqual(package.archiveHash, GraphStore.hash(try Data(contentsOf: url)))
        let original = try await store.immutableData(kind: "packageArchive", id: package.archiveHash)
        XCTAssertEqual(original, try Data(contentsOf: url))
        XCTAssertTrue(package.integrityNotes.contains { $0.contains("checksums verified") })
        let object = NauticaObject(type: "requirement", name: "Integration test proposition")
        try await store.saveObject(object)
        let draft = AuditDraft(packageID: package.id, name: "Real package / synthetic input integration test", propositions: "Test host freezing only; no conformance determination requested", scope: "Synthetic object", objectIDs: [object.id], intakeTranscript: "PRIVATE-INTAKE")
        try await store.saveAuditDraft(draft)
        let projection = try await store.reviewProjection(draft)
        let frozen = try await store.freezeAudit(draft, reviewedHash: GraphStore.hash(GraphStore.encode(projection)), command: package.manifest.freeze_command)
        let exported = try await store.exportAuditContext(auditID: frozen.id, parent: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("methodology/AUDIT-LAUNCH-PROMPT.md").path))
        XCTAssertFalse(String(data: frozen.context, encoding: .utf8)!.contains("PRIVATE-INTAKE"))
        print("REAL_PACKAGE_CHECK: \(package.originalFilename) SHA256=\(package.archiveHash) \(package.integrityNotes.joined(separator: " | "))")
    }
}
