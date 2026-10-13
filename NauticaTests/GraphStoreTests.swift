import XCTest
import GRDB
@testable import Nautica

final class GraphStoreTests: XCTestCase {
    private var directory: URL!
    private var store: GraphStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GraphStore(url: directory.appendingPathComponent("Graph.sqlite"))
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: directory) }

    func testSharedIdentityViewsAndPinDeletionPersistAcrossReopen() async throws {
        let object = NauticaObject(type: "evidence", name: "E-17")
        try await store.saveObject(object)
        let a = NauticaView(name: "Habitat", definition: GraphViewDefinition(memberIDs: [object.id]))
        let b = NauticaView(name: "September", definition: GraphViewDefinition(memberIDs: [object.id]))
        try await store.saveView(a); try await store.saveView(b)
        try await store.pin(.view, id: a.id.uuidString)
        try await store.pin(.view, id: b.id.uuidString)
        let originalPins = try await store.pins()
        try await store.reorderPins(originalPins.reversed().map(\.id))
        let reopened = GraphStore(url: directory.appendingPathComponent("Graph.sqlite"))
        var graph = try await reopened.snapshot()
        XCTAssertEqual(graph.objects.count, 1)
        XCTAssertEqual(graph.resolve(a.definition).map(\.id), [object.id])
        XCTAssertEqual(graph.resolve(b.definition).map(\.id), [object.id])
        let pins = try await reopened.pins()
        XCTAssertEqual(pins.map(\.id), originalPins.reversed().map(\.id))
        try await reopened.removePin(pins[0].id)
        let viewsAfterUnpin = try await reopened.views()
        XCTAssertEqual(viewsAfterUnpin.count, 2)
        try await reopened.deleteView(a.id)
        graph = try await reopened.snapshot()
        XCTAssertEqual(graph.objects, [object])
        XCTAssertEqual(graph.resolve(b.definition).map(\.id), [object.id])
        let finalPins = try await reopened.pins()
        XCTAssertTrue(finalPins.isEmpty)
    }

    func testSmartRelationshipCombinedViewsAndInferredProvenance() async throws {
        let project = NauticaObject(type: "project", name: "Habitat")
        let requirement = NauticaObject(type: "requirement", name: "R-17", metadata: ["status": "open", "priority": "high"], tags: ["review"])
        let evidence = NauticaObject(type: "evidence", name: "E-22", metadata: ["status": "open", "priority": "low"])
        let inferred = NauticaObject(type: "finding", name: "Inferred")
        for object in [project, requirement, evidence, inferred] { try await store.saveObject(object) }
        let edges = [
            NauticaRelationship(type: "governedBy", sourceObjectID: project.id, targetObjectID: requirement.id, provenance: .init(establishedBy: "tester", source: "contract")),
            NauticaRelationship(type: "supportsRequirement", sourceObjectID: evidence.id, targetObjectID: requirement.id, provenance: .init(origin: .imported, establishedBy: "import", source: "evidence register")),
            NauticaRelationship(type: "relatedTo", sourceObjectID: requirement.id, targetObjectID: inferred.id, provenance: .init(origin: .inferred, establishedBy: "model", source: "hypothesis", confidence: 0.4))
        ]
        for edge in edges { try await store.saveRelationship(edge) }
        let reopened = GraphStore(url: directory.appendingPathComponent("Graph.sqlite"))
        let graph = try await reopened.snapshot()
        XCTAssertEqual(Set(graph.relationships.map(\.id)), Set(edges.map(\.id)))
        XCTAssertEqual(graph.relationships.first { $0.id == edges[2].id }?.provenance.confidence, 0.4)
        let smart = GraphViewDefinition(kind: .smart, filters: [.init(field: "status", value: "open"), .init(field: "priority", comparison: .atLeast, value: "high"), .init(field: "tag", value: "review")])
        XCTAssertEqual(graph.resolve(smart).map(\.id), [requirement.id])
        var related = GraphViewDefinition(kind: .relationship, traversal: .init(startObjectID: project.id))
        XCTAssertEqual(Set(graph.resolve(related).map(\.id)), Set([project.id, requirement.id, evidence.id]))
        related.traversal?.maxDepth = 1
        XCTAssertEqual(Set(graph.resolve(related).map(\.id)), Set([project.id, requirement.id]))
        related.traversal?.maxDepth = 4
        related.traversal?.includeInferred = true
        XCTAssertEqual(graph.resolve(related).count, 4)
        related.filters = smart.filters
        XCTAssertEqual(graph.resolve(related).map(\.id), [requirement.id])
        related.traversal?.direction = .incoming
        XCTAssertEqual(graph.resolve(related).count, 0)
    }

    func testHistoricalRevisionAndEvidenceCaptureDoNotReadLiveFile() async throws {
        let old = Date(timeIntervalSince1970: 100)
        var object = NauticaObject(type: "requirement", name: "Old requirement")
        try await store.saveObject(object, at: old)
        object.name = "Changed requirement"
        try await store.saveObject(object, at: old.addingTimeInterval(100))
        let historical = try await store.snapshot(asOf: old.addingTimeInterval(1))
        XCTAssertEqual(historical.objects.first?.name, "Old requirement")
        let file = directory.appendingPathComponent("record.txt")
        try Data("Original evidence".utf8).write(to: file)
        let evidence = try await store.registerFile(file, captureEvidence: true)
        let reference = try await store.registerFile(file, captureEvidence: false)
        XCTAssertEqual(evidence.id, reference.id)
        try Data("Later evidence".utf8).write(to: file)
        let stored = try await store.immutableData(kind: "evidence", id: evidence.evidenceHash!)
        XCTAssertEqual(String(data: stored, encoding: .utf8), "Original evidence")
        let updated = try await store.registerFile(file, captureEvidence: true)
        XCTAssertEqual(updated.id, evidence.id)
        XCTAssertNotEqual(updated.evidenceHash, evidence.evidenceHash)
    }

    func testDanglingRelationshipsRejectedAndSubsystemRegistered() async throws {
        XCTAssertEqual(SubsystemRegistry.all.map(\.id), ["paf"])
        try await store.pin(.subsystem, id: "paf")
        let pins = try await store.pins()
        XCTAssertEqual(pins.first?.targetID, "paf")
        let bad = NauticaRelationship(type: "relatedTo", sourceObjectID: UUID(), targetObjectID: UUID(), provenance: .init(establishedBy: "tester", source: "test"))
        do { try await store.saveRelationship(bad); XCTFail("Dangling endpoints accepted") } catch {}
        let queue = try await store.database()
        let object = NauticaObject(type: "test", name: "Original")
        try await store.saveObject(object)
        do { try await queue.write { try $0.execute(sql: "DELETE FROM objects") }; XCTFail("Graph history was deleted") } catch {}
    }

    func testDeliberateErasureLifecycleAndWorkspacePortability() async throws {
        let file = directory.appendingPathComponent("secret.txt")
        try Data("Sensitive payload".utf8).write(to: file)
        let object = try await store.registerFile(file, captureEvidence: true)
        let other = NauticaObject(type: "project", name: "Public Project")
        try await store.saveObject(other)
        let edge = NauticaRelationship(
            type: "references",
            sourceObjectID: other.id,
            targetObjectID: object.id,
            provenance: .init(establishedBy: "auditor", source: "evidence")
        )
        try await store.saveRelationship(edge)

        let initialSnapshot = try await store.snapshot()
        XCTAssertEqual(initialSnapshot.objects.count, 2)
        XCTAssertEqual(initialSnapshot.relationships.count, 1)

        // Verify evidence blob exists
        let hash = try XCTUnwrap(object.evidenceHash)
        let blob = try await store.immutableData(kind: "evidence", id: hash)
        XCTAssertEqual(String(data: blob, encoding: .utf8), "Sensitive payload")

        // Execute deliberate erasure
        let receipt = try await store.purgeObject(id: object.id, reason: "GDPR right to erasure")
        XCTAssertEqual(receipt.targetObjectID, object.id)
        XCTAssertEqual(receipt.reason, "GDPR right to erasure")

        // Verify active snapshot filters out purged object and dangling edge
        let purgedSnapshot = try await store.snapshot()
        XCTAssertEqual(purgedSnapshot.objects.count, 1)
        XCTAssertEqual(purgedSnapshot.objects.first?.id, other.id)
        XCTAssertEqual(purgedSnapshot.relationships.count, 0)

        // Verify sensitive payload is expunged from immutable table
        do {
            _ = try await store.immutableData(kind: "evidence", id: hash)
            XCTFail("Sensitive evidence blob was not expunged")
        } catch {}

        // Verify verifiable deletion receipt is preserved
        let receipts = try await store.deletionReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.id, receipt.id)

        // Test workspace export and round-trip restore into another store
        let exportData = try await store.exportWorkspace()
        let secondDir = directory.appendingPathComponent("SecondStore")
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        let secondStore = GraphStore(url: secondDir.appendingPathComponent("Graph.sqlite"))
        try await secondStore.importWorkspace(from: exportData)

        let importedSnapshot = try await secondStore.snapshot()
        XCTAssertEqual(importedSnapshot.objects.count, 1)
        XCTAssertEqual(importedSnapshot.objects.first?.id, other.id)
        let importedReceipts = try await secondStore.deletionReceipts()
        XCTAssertEqual(importedReceipts.count, 1)
        XCTAssertEqual(importedReceipts.first?.targetObjectID, object.id)
    }
}
