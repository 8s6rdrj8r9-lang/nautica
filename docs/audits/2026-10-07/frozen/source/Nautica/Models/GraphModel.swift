import Foundation

struct NauticaObject: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var type: String
    var name: String
    var metadata: [String: String] = [:]
    var tags: [String] = []
    var lifecycle = "active"
    var resourceURL: URL?
    /// Immutable bytes captured when explicitly registering evidence, not a live file reference.
    var evidenceHash: String?
}

struct RelationshipProvenance: Codable, Equatable, Sendable {
    enum Origin: String, Codable, CaseIterable, Sendable { case userDefined, imported, inferred, auditProduced }
    var origin: Origin = .userDefined
    var establishedBy: String
    var source: String
    var createdAt = Date()
    var confidence: Double?
    var status = "asserted"
}

struct NauticaRelationship: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var type: String
    var sourceObjectID: UUID
    var targetObjectID: UUID
    var metadata: [String: String] = [:]
    var provenance: RelationshipProvenance
    var lifecycle = "active"
}

struct GraphFilter: Codable, Equatable, Sendable {
    enum Comparison: String, Codable, CaseIterable, Sendable { case equals, contains, atLeast }
    var field: String
    var comparison: Comparison = .equals
    var value: String

    func matches(_ object: NauticaObject) -> Bool {
        let actual: String
        switch field {
        case "type": actual = object.type
        case "name": actual = object.name
        case "lifecycle": actual = object.lifecycle
        case "tag": return object.tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        default: actual = object.metadata[field] ?? ""
        }
        switch comparison {
        case .equals: return actual.caseInsensitiveCompare(value) == .orderedSame
        case .contains: return actual.localizedCaseInsensitiveContains(value)
        case .atLeast:
            let priorities = ["low": 1.0, "medium": 2.0, "high": 3.0, "critical": 4.0]
            guard let a = Double(actual) ?? priorities[actual.lowercased()],
                  let b = Double(value) ?? priorities[value.lowercased()] else { return false }
            return a >= b
        }
    }
}

struct GraphTraversal: Codable, Equatable, Sendable {
    enum Direction: String, Codable, CaseIterable, Sendable { case outgoing, incoming, both }
    var startObjectID: UUID
    var relationshipTypes: [String] = []
    var objectTypes: [String] = []
    var direction: Direction = .both
    var maxDepth = 4
    var includeStart = true
    var includeInferred = false
}

struct GraphViewDefinition: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case collection = "Collection", smart = "Smart View", relationship = "Relationship View" }
    var kind: Kind = .collection
    var memberIDs: [UUID] = []
    var filters: [GraphFilter] = []
    var traversal: GraphTraversal?
    /// Explicit members are unioned with the query result, then filters apply to both.
    var includesArchived = false
}

struct NauticaView: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var definition = GraphViewDefinition()
    var symbol = "square.stack"
    var userConfiguration: [String: String] = [:]
}

struct DockPin: Identifiable, Codable, Equatable, Sendable {
    enum TargetType: String, Codable, CaseIterable, Sendable { case view, subsystem, object, action }
    var id = UUID()
    var targetType: TargetType
    var targetID: String
    var position = 0
    var labelOverride: String?
    var symbolOverride: String?
}

struct NauticaSubsystem: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
}

enum SubsystemRegistry {
    static let all = [NauticaSubsystem(id: "paf", name: "PAF", symbol: "checkmark.shield")]
}

struct GraphSnapshot: Codable, Equatable, Sendable {
    var objects: [NauticaObject] = []
    var relationships: [NauticaRelationship] = []
    var asOf: Date = .now

    func resolve(_ definition: GraphViewDefinition) -> [NauticaObject] {
        var selected = Set(definition.memberIDs)
        if let traversal = definition.traversal {
            var visited: Set<UUID> = [traversal.startObjectID]
            var frontier = visited
            for _ in 0..<max(0, min(traversal.maxDepth, 16)) {
                var next = Set<UUID>()
                for edge in relationships where edge.lifecycle == "active" {
                    guard traversal.relationshipTypes.isEmpty || traversal.relationshipTypes.contains(edge.type),
                          traversal.includeInferred || edge.provenance.origin != .inferred else { continue }
                    if traversal.direction != .incoming && frontier.contains(edge.sourceObjectID) { next.insert(edge.targetObjectID) }
                    if traversal.direction != .outgoing && frontier.contains(edge.targetObjectID) { next.insert(edge.sourceObjectID) }
                }
                next.subtract(visited)
                if next.isEmpty { break }
                visited.formUnion(next)
                frontier = next
            }
            if !traversal.includeStart { visited.remove(traversal.startObjectID) }
            selected.formUnion(objects.filter { visited.contains($0.id) && (traversal.objectTypes.isEmpty || traversal.objectTypes.contains($0.type)) }.map(\.id))
        } else if definition.kind == .smart {
            selected.formUnion(objects.map(\.id))
        }
        return objects.filter { object in
            selected.contains(object.id) && (definition.includesArchived || object.lifecycle == "active") && definition.filters.allSatisfy { $0.matches(object) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum GraphError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
