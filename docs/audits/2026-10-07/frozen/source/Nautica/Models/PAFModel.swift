import Foundation

struct PAFManifest: Codable, Equatable, Sendable {
    let framework: String
    let package_format: Int
    let framework_version: String
    let release: String
    let interaction_model: String
    let entry_points: [String: String]
    let framework_root: String
    let templates: [String: String]
    let freeze_command: String
    let completion_marker: String
    var auditor_files: [String]? = nil
    var distribution_version: String? = nil
    var package_layout: String? = nil
}

struct PAFPackage: Identifiable, Codable, Sendable {
    var id: String // Content hash of original archive, manifest, and explicit supplements.
    var archiveHash: String
    var originalFilename: String
    var manifest: PAFManifest
    var files: [String: Data]
    var importedAt: Date
    var blockers: [String]
    var integrityNotes: [String]
    var supplementalNames: [String]
    var ready: Bool { blockers.isEmpty }
    var label: String { "\(manifest.framework) \(manifest.framework_version) · Kit \(manifest.distribution_version ?? "unspecified") · \(id.prefix(8))" }
}

struct AuditDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var packageID: String
    var name = "New Audit"
    var auditedDate = Date()
    /// Time of the graph revision to project, independent of the proposition's audited date.
    var graphAsOf = Date()
    var propositions = ""
    var scope = ""
    var exclusions = ""
    var governingCriteria = ""
    var evidenceRules = ""
    var assurance = ""
    var limitations = ""
    var ambiguities = ""
    var externalResearchAuthorized = false
    var objectIDs: [UUID] = []
    var relationshipIDs: [UUID] = []
    var authorizedEvidenceIDs: [UUID] = []
    var intakeTranscript = ""
}

/// Deliberately has no transcript field. This is the full auditor-facing boundary.
struct AuditProjection: Codable, Equatable, Sendable {
    let auditID: UUID
    let name: String
    let packageID: String
    let auditedDate: Date
    let graphAsOf: Date
    let propositions: String
    let scope: String
    let exclusions: String
    let governingCriteria: String
    let evidenceRules: String
    let assurance: String
    let limitations: String
    let ambiguities: String
    let externalResearchAuthorized: Bool
    let objects: [NauticaObject]
    let relationships: [NauticaRelationship]
    let evidence: [String: Data]
}

struct FrozenAudit: Identifiable, Codable, Sendable {
    let id: UUID
    let projection: AuditProjection
    let projectionHash: String
    let frozenAt: Date
    /// A new standalone input, not a conversation continuation.
    let context: Data
    let contextHash: String
    let executionMode: String
}

struct FrozenAuditResponse: Codable, Sendable {
    let auditID: UUID
    let report: Data
    let reportHash: String
    let capturedAt: Date
    let auditor: String
    let contextBoundaryDeclaration: String
}

/// Structured links must be explicitly supported by an exact excerpt in the frozen report.
struct AuditArtifactRequest: Sendable {
    let type: String
    let title: String
    let reportExcerpt: String
}
