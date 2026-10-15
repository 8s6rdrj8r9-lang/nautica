import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PAFWorkspaceView: View {
    @Bindable var model: GraphWorkspaceModel
    @State private var importing = false
    @State private var intake: AuditDraft?
    @State private var selectedAudit: FrozenAudit?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("PAF", systemImage: "checkmark.shield").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Import Package…") { importing = true }
            }
            Text("Audit your Objects and Relationships using a reviewed, frozen set of inputs.").foregroundStyle(.secondary)
            Text("Import a package, review the inputs, then freeze and export them to an independent auditor. Nautica does not include a model runner.")
                .font(.callout).foregroundStyle(.secondary)
            if model.packages.isEmpty && model.drafts.isEmpty && model.audits.isEmpty {
                ContentUnavailableView {
                    Label("No Audit Packages", systemImage: "checkmark.shield")
                } description: {
                    Text("Import a PAF package to start an audit. Your draft inputs can be reviewed before anything is frozen.")
                } actions: {
                    Button("Import Package…") { importing = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            List {
                Section("Installed packages") {
                    ForEach(model.packages) { package in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(package.label).font(.headline)
                            Text("Archive SHA-256: \(package.archiveHash)").font(.caption.monospaced()).textSelection(.enabled)
                            ForEach(package.integrityNotes, id: \.self) { Text($0).font(.caption) }
                            ForEach(package.blockers, id: \.self) { Text($0).foregroundStyle(.orange).font(.caption) }
                            Button("Begin Interactive Intake") { intake = AuditDraft(packageID: package.id) }
                            if !package.ready { Text("Intake may be prepared; freeze is blocked until a complete package is imported.").font(.caption) }
                        }.padding(.vertical, 8).buttonStyle(.borderless).accessibilityElement(children: .contain)
                    }
                }
                Section("Intake drafts") {
                    ForEach(model.drafts.filter { draft in !model.audits.contains { $0.id == draft.id } }) { draft in
                        Button(draft.name) { intake = draft }
                    }
                }
                Section("Frozen audits") {
                    ForEach(model.audits) { audit in
                        Button { selectedAudit = audit } label: {
                            VStack(alignment: .leading) {
                                Text(audit.projection.name)
                                Text("Frozen \(audit.frozenAt.formatted()) · \(audit.projectionHash.prefix(12))").font(.caption)
                            }
                        }
                    }
                }
            }
            }
            Divider()
            Text("Execution uses a standalone export for an independent auditor. Nautica does not currently include a model runner; external auditor context isolation must be recorded honestly.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        .sheet(isPresented: $importing) { PAFImportView(model: model) }
        .sheet(item: $intake) { AuditIntakeView(model: model, original: $0) }
        .sheet(item: $selectedAudit) { FrozenAuditView(model: model, audit: $0) }
    }
}

struct PAFImportView: View {
    @Bindable var model: GraphWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var archive: URL?
    @State private var manifest: URL?
    @State private var supplements: [URL] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import PAF Package").font(.title2)
            Text("Import the interactive ZIP containing paf-package.json. For separately supplied material, select the original ZIP, manifest, and supplemental files. Content is preserved without renaming or patching missing entry points.")
            Button(archive?.lastPathComponent ?? "Choose ZIP…") { archive = selectFile(types: [.zip]) }
            Button(manifest?.lastPathComponent ?? "Optional sidecar paf-package.json…") { manifest = selectFile(types: [.json]) }
            Button("Add Supplemental File…") { if let url = selectFile() { supplements.append(url) } }
            ForEach(supplements, id: \.self) { Text($0.lastPathComponent).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Import & Verify") {
                    guard let archive else { return }
                    model.run { _ = try await model.store.importPAF(archive: archive, manifest: manifest, supplements: supplements); dismiss() }
                }.disabled(archive == nil || model.busy)
            }
        }.padding(24).frame(width: 580)
    }
}

@MainActor private func selectFile(types: [UTType] = []) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    if !types.isEmpty { panel.allowedContentTypes = types }
    return panel.runModal() == .OK ? panel.url : nil
}

struct AuditIntakeView: View {
    @Bindable var model: GraphWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AuditDraft
    @State private var step = 0
    @State private var reviewed: AuditProjection?
    @State private var boundary = GraphSnapshot()
    @State private var inputError: String?
    private let steps = ["Objective", "Governing material", "Boundary & evidence", "Limitations", "Review"]
    init(model: GraphWorkspaceModel, original: AuditDraft) { self.model = model; _draft = State(initialValue: original) }
    private var package: PAFPackage? { model.packages.first { $0.id == draft.packageID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interactive Audit Intake").font(.title2)
            Text("\(step + 1) of \(steps.count) · \(steps[step])").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if step == 0 { objective }
                    if step == 1 { governing }
                    if step == 2 { boundaryEditor }
                    if step == 3 { limitations }
                    if step == 4 { review }
                }.padding(4)
            }
            if let inputError { Text(inputError).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Save & Close") { model.run { try await model.store.saveAuditDraft(draft); dismiss() } }
                Spacer()
                Button("Back") { step -= 1; reviewed = nil }.disabled(step == 0)
                if step < 4 {
                    Button("Continue") {
                        inputError = nil
                        Task {
                            do {
                                try await model.store.saveAuditDraft(draft)
                                if step == 1 { boundary = try await model.store.snapshot(asOf: draft.graphAsOf) }
                                if step == 3 { reviewed = try await model.store.reviewProjection(draft) }
                                step += 1
                            } catch { inputError = error.localizedDescription }
                        }
                    }
                } else {
                    Button("FREEZE & START AUDIT") {
                        guard let reviewed else { return }
                        model.run {
                            _ = try await model.store.freezeAudit(draft, reviewedHash: GraphStore.hash(GraphStore.encode(reviewed)), command: "FREEZE & START AUDIT")
                            dismiss()
                        }
                    }.disabled(reviewed == nil || package?.ready != true || model.busy)
                }
            }
        }.padding(24).frame(width: 780, height: 700)
        .task { do { boundary = try await model.store.snapshot(asOf: draft.graphAsOf) } catch { inputError = error.localizedDescription } }
        .onChange(of: draft) { _, _ in reviewed = nil }
        .onChange(of: draft.auditedDate) { _, date in draft.graphAsOf = min(date, Date()) }
    }
    private var objective: some View {
        Group {
            TextField("Audit name", text: $draft.name)
            DatePicker("Audited date / period anchor", selection: $draft.auditedDate)
            TextField("Exact requested propositions", text: $draft.propositions, axis: .vertical).lineLimit(4...8)
            TextField("Scope and review boundary (include period end when applicable)", text: $draft.scope, axis: .vertical).lineLimit(3...6)
            TextField("Explicit exclusions", text: $draft.exclusions, axis: .vertical)
            DisclosureGroup("Package intake instructions") {
                Text(intakeInstructions).font(.caption).textSelection(.enabled)
            }
            Text("Intake records the questions and supplied context. It does not determine conformance, sufficiency, closure, or achieved assurance.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var intakeInstructions: String {
        guard let package else { return "Package unavailable." }
        let paths = [package.manifest.entry_points["audit_intake"], package.manifest.entry_points["audit_initiation"]].compactMap { $0 }
        let content = paths.compactMap { path in package.files[path].flatMap { String(data: $0, encoding: .utf8) } }.joined(separator: "\n\n")
        return content.isEmpty ? "Referenced intake entry points are missing from this package. See package validation messages." : content
    }
    private var governing: some View {
        Group {
            TextField("Governing criteria and sources", text: $draft.governingCriteria, axis: .vertical).lineLimit(4...8)
            TextField("Applicable evidence rules and sources (leave unspecified if unknown)", text: $draft.evidenceRules, axis: .vertical).lineLimit(3...6)
            TextField("Applicable profile / target assurance, if supported", text: $draft.assurance, axis: .vertical)
            Text("Distinguish assertions from documentary evidence; identify the source of each governing condition. Do not invent conditions to fill a blank.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var boundaryEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Use graph state recorded at", selection: $draft.graphAsOf, in: ...Date())
            Button("Load Historical State") {
                Task { do { boundary = try await model.store.snapshot(asOf: draft.graphAsOf) } catch { inputError = error.localizedDescription } }
            }
            Text("This date selects recorded graph revisions. It is separate from the proposition's audited date; later historical evidence and its limitations must be explicit.").font(.caption)
            Text("Include Objects and authorize captured evidence").font(.headline)
            ForEach(boundary.objects) { object in
                HStack {
                    Toggle("\(object.name) (\(object.type))", isOn: membership(object.id, ids: $draft.objectIDs))
                    if object.evidenceHash != nil && draft.objectIDs.contains(object.id) {
                        Toggle("Authorize evidence bytes", isOn: membership(object.id, ids: $draft.authorizedEvidenceIDs))
                    }
                }
            }
            Text("Include Relationships").font(.headline)
            ForEach(boundary.relationships.filter { draft.objectIDs.contains($0.sourceObjectID) && draft.objectIDs.contains($0.targetObjectID) }) { edge in
                Toggle("\(objectName(edge.sourceObjectID)) → \(edge.type) → \(objectName(edge.targetObjectID)) [\(edge.provenance.origin.rawValue)]", isOn: membership(edge.id, ids: $draft.relationshipIDs))
            }
        }
    }
    private func objectName(_ id: UUID) -> String { boundary.objects.first { $0.id == id }?.name ?? id.uuidString }
    private func membership(_ id: UUID, ids: Binding<[UUID]>) -> Binding<Bool> {
        Binding(get: { ids.wrappedValue.contains(id) }, set: { selected in
            ids.wrappedValue.removeAll { $0 == id }
            if selected { ids.wrappedValue.append(id) }
            let boundaryIDs = Set(draft.objectIDs)
            draft.authorizedEvidenceIDs.removeAll { !boundaryIDs.contains($0) }
            draft.relationshipIDs.removeAll { edgeID in
                guard let edge = boundary.relationships.first(where: { $0.id == edgeID }) else { return true }
                return !boundaryIDs.contains(edge.sourceObjectID) || !boundaryIDs.contains(edge.targetObjectID)
            }
        })
    }
    private var limitations: some View {
        Group {
            Toggle("External evidence / research is authorized", isOn: $draft.externalResearchAuthorized)
            TextField("Known limitations and historical evidence availability", text: $draft.limitations, axis: .vertical).lineLimit(3...6)
            TextField("Unresolved ambiguities and conflicts", text: $draft.ambiguities, axis: .vertical).lineLimit(3...6)
            Text("Private intake discussion — excluded from auditor context").font(.headline)
            TextEditor(text: $draft.intakeTranscript).frame(height: 150).border(.separator)
        }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reviewed {
                Text("Audit Input Review").font(.headline)
                Text("\(reviewed.objects.count) Objects · \(reviewed.relationships.count) Relationships · \(reviewed.evidence.count) authorized evidence files")
                Text("Review all metadata, provenance, and evidence below. Freeze will save these exact inputs. The private intake discussion is excluded.")
                ForEach(reviewed.evidence.keys.sorted(), id: \.self) { hash in
                    DisclosureGroup("Evidence \(hash.prefix(12)) · \(reviewed.evidence[hash]!.count) bytes") {
                        Text(String(data: reviewed.evidence[hash]!, encoding: .utf8) ?? "Binary evidence. Its original bytes are included in the frozen export.").font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Text(projectionText(reviewed)).font(.caption.monospaced()).textSelection(.enabled)
                if package?.ready != true { Text("Freeze blocked: import a complete compatible package before execution.").foregroundStyle(.orange) }
            }
        }
    }
    private func projectionText(_ projection: AuditProjection) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return (try? String(data: encoder.encode(projection), encoding: .utf8)) ?? "Unable to render projection"
    }
}

struct FrozenAuditView: View {
    @Bindable var model: GraphWorkspaceModel
    let audit: FrozenAudit
    @Environment(\.dismiss) private var dismiss
    @State private var response: FrozenAuditResponse?
    @State private var auditor = ""
    @State private var boundaryDeclaration = ""
    @State private var artifactTitle = ""
    @State private var artifactType = "finding"
    @State private var excerpt = ""
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(audit.projection.name).font(.title2)
            Text("Frozen at \(audit.frozenAt.formatted())").font(.caption)
            Text("Projection SHA-256: \(audit.projectionHash)").font(.caption.monospaced()).textSelection(.enabled)
            Button("Export Clean Auditor Context…") { exportContext() }
            Text("Give the export to a new independent auditor session. This export excludes the intake transcript; Nautica cannot verify the external session's prior context or behavior.").font(.caption).foregroundStyle(.secondary)
            if let response {
                Text("AUDITOR RESPONSE FROZEN").font(.headline)
                Text("\(response.auditor) · \(response.contextBoundaryDeclaration)").font(.caption)
                ScrollView { Text(String(data: response.report, encoding: .utf8) ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 180)
                Picker("Index artifact", selection: $artifactType) { Text("Finding").tag("finding"); Text("Verification Requirement").tag("verificationRequirement") }
                TextField("Artifact title", text: $artifactTitle)
                TextField("Exact supporting report excerpt", text: $excerpt, axis: .vertical)
                Button("Add Supported Artifact to Graph") {
                    model.run {
                        _ = try await model.store.indexAuditArtifact(auditID: audit.id, request: AuditArtifactRequest(type: artifactType, title: artifactTitle, reportExcerpt: excerpt))
                        status = "Artifact indexed with report provenance."
                    }
                }.disabled(excerpt.isEmpty || artifactTitle.isEmpty)
            } else {
                TextField("Auditor identity / execution reference", text: $auditor)
                TextField("Actual context boundary and limitations", text: $boundaryDeclaration, axis: .vertical)
                Button("Capture Frozen Auditor Response…") {
                    guard let url = selectFile() else { return }
                    model.run {
                        let bytes = try PAFPackageLoader.boundedRead(url)
                        response = try await model.store.captureAuditResponse(auditID: audit.id, report: bytes, auditor: auditor, boundaryDeclaration: boundaryDeclaration)
                    }
                }.disabled(auditor.isEmpty || boundaryDeclaration.isEmpty)
            }
            Text(status).font(.caption)
            HStack { Spacer(); Button("Done") { dismiss() } }
        }.padding(24).frame(width: 720)
        .task {
            do {
                let responses = try await model.store.frozenRecords("response", FrozenAuditResponse.self)
                response = responses.first { $0.auditID == audit.id }
            } catch { model.error = error.localizedDescription }
        }
    }
    private func exportContext() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        model.run {
            let directory = try await model.store.exportAuditContext(auditID: audit.id, parent: parent)
            status = "Exported to \(directory.path)"
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }
}
