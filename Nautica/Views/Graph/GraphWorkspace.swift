import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class GraphWorkspaceModel {
    static let shared = GraphWorkspaceModel()
    var graph = GraphSnapshot()
    var views: [NauticaView] = []
    var pins: [DockPin] = []
    var packages: [PAFPackage] = []
    var drafts: [AuditDraft] = []
    var audits: [FrozenAudit] = []
    var error: String?
    var busy = false
    let store: GraphStore
    init(store: GraphStore = .shared) { self.store = store }
    func refresh() async throws {
        graph = try await store.snapshot()
        views = try await store.views()
        pins = try await store.pins()
        packages = try await store.pafPackages()
        drafts = try await store.auditDrafts()
        audits = try await store.frozenAudits()
    }
    func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await work(); try await refresh() } catch { self.error = error.localizedDescription }
        }
    }
    func label(_ pin: DockPin) -> String {
        if let override = pin.labelOverride { return override }
        switch pin.targetType {
        case .view: return views.first { $0.id.uuidString == pin.targetID }?.name ?? "Missing View"
        case .object: return graph.objects.first { $0.id.uuidString == pin.targetID }?.name ?? "Missing Object"
        case .subsystem: return SubsystemRegistry.all.first { $0.id == pin.targetID }?.name ?? "Missing Subsystem"
        case .action: return "New View"
        }
    }
    func symbol(_ pin: DockPin) -> String {
        pin.symbolOverride ?? (pin.targetType == .subsystem ? "checkmark.shield" : pin.targetType == .object ? "doc" : pin.targetType == .action ? "plus" : "square.stack")
    }
}

struct GraphApplicationShell: View {
    @State private var model = GraphWorkspaceModel.shared
    @AppStorage("Nautica.WorkspaceMode") private var workspaceMode: String = "files"
    @State private var destination: DockPin?
    @State private var newView: NauticaView?
    @AppStorage("Nautica.RightDock.Enabled") private var dockEnabled = true
    var body: some View {
        VStack(spacing: 0) {
            if workspaceMode == "files" {
                BrowserView()
            } else {
                HStack(spacing: 0) {
                    if workspaceMode == "paf" || destination?.targetType == .subsystem {
                        PAFWorkspaceView(model: model)
                    } else {
                        GraphBrowserView(model: model, destination: destination)
                    }
                    if dockEnabled {
                        Divider()
                        RightDockView(model: model) { pin in
                            if pin.targetType == .action {
                                newView = NauticaView(name: "")
                            } else if pin.targetType == .subsystem && pin.targetID == "paf" {
                                destination = pin
                                workspaceMode = "paf"
                            } else {
                                destination = pin
                                workspaceMode = "graph"
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: Binding(get: { workspaceMode }, set: { workspaceMode = $0; destination = nil })) {
                    Label("Files", systemImage: "folder").tag("files")
                    Label("Objects & Views", systemImage: "point.3.connected.trianglepath.dotted").tag("graph")
                    Label("PAF", systemImage: "checkmark.shield").tag("paf")
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Working") }
                if workspaceMode == "graph" {
                    Button("New View", systemImage: "plus") { newView = NauticaView(name: "") }
                }
                SettingsLink { Label("Settings", systemImage: "gear") }
            }
        }
        .frame(minWidth: 900, minHeight: 550)
        .task { do { try await model.refresh() } catch { model.error = error.localizedDescription } }
        .sheet(item: $newView) { GraphViewBuilder(model: model, original: $0) }
        .alert("Nautica", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct RightDockView: View {
    @Bindable var model: GraphWorkspaceModel
    let open: (DockPin) -> Void
    @AppStorage("Nautica.RightDock.Labels") private var showLabels = true
    @AppStorage("Nautica.RightDock.Compact") private var compact = false
    @FocusState private var focused: UUID?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: compact ? 4 : 8) {
                    ForEach(model.pins) { pin in
                        Button { focused = pin.id; open(pin) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: model.symbol(pin)).font(compact ? .body : .title3)
                                if showLabels && !compact { Text(model.label(pin)).font(.caption).lineLimit(3).multilineTextAlignment(.center) }
                            }.frame(maxWidth: .infinity).padding(.vertical, compact ? 8 : 12)
                        }
                        .buttonStyle(.bordered)
                        .focusable()
                        .focused($focused, equals: pin.id)
                        .accessibilityLabel(model.label(pin))
                        .help(model.label(pin))
                        .contextMenu {
                            Button("Remove from Dock") { model.run { try await model.store.removePin(pin.id) } }
                        }
                    }
                    if model.pins.isEmpty {
                        SettingsLink {
                            Label("Configure Pins", systemImage: "pin")
                                .font(.caption).multilineTextAlignment(.center)
                        }
                        .help("Configure pinned navigation for Objects & Views and PAF in Settings")
                    }
                }
                .padding(6)
                .frame(minHeight: max(0, geometry.size.height), alignment: .center)
            }
            .onMoveCommand { direction in
                let index = model.pins.firstIndex { $0.id == focused } ?? -1
                if direction == .down, !model.pins.isEmpty { focused = model.pins[min(index + 1, model.pins.count - 1)].id }
                if direction == .up, !model.pins.isEmpty { focused = model.pins[max(index - 1, 0)].id }
            }
        }.frame(width: compact || !showLabels ? 52 : 108)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right Dock")
    }
}

struct GraphBrowserView: View {
    @Bindable var model: GraphWorkspaceModel
    var destination: DockPin?
    @State private var selectedView: UUID?
    @State private var selectedObject: UUID?
    @State private var search = ""
    @State private var editingObject: NauticaObject?
    @State private var editingView: NauticaView?
    @State private var showRelationship = false
    private var currentView: NauticaView? {
        model.views.first { $0.id == selectedView }
    }
    private var objects: [NauticaObject] {
        let candidates: [NauticaObject]
        if let selectedObject { candidates = model.graph.objects.filter { $0.id == selectedObject } }
        else if let view = currentView { candidates = model.graph.resolve(view.definition) }
        else { candidates = model.graph.objects.filter { $0.lifecycle == "active" } }
        return candidates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }) }
    }
    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { selectedView }, set: { selectedView = $0; selectedObject = nil })) {
                Text("All Objects").tag(UUID?.none)
                Section("Views") {
                    ForEach(model.views) { view in
                        Label(view.name, systemImage: view.symbol).tag(Optional(view.id))
                            .contextMenu {
                                Button("Configure / Rename View") { editingView = view }
                                Button("Pin to Right Dock") { model.run { try await model.store.pin(.view, id: view.id.uuidString) } }
                                Button("Delete View", role: .destructive) { model.run { try await model.store.deleteView(view.id) } }
                            }
                    }
                }
            }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(currentView?.name ?? "Objects").font(.title2).fontWeight(.semibold)
                    Spacer()
                    if let view = currentView { Button("Configure") { editingView = view } }
                    Button("New Object") { editingObject = NauticaObject(type: "document", name: "") }
                    Menu("Register File") {
                        Button("File Reference…") { registerFile(evidence: false) }
                        Button("Capture Evidence…") { registerFile(evidence: true) }
                    }.fixedSize()
                    Button("Add Relationship") { showRelationship = true }.disabled(model.graph.objects.count < 2)
                        .help(model.graph.objects.count < 2 ? "Create at least two Objects to add a relationship" : "Connect two Objects")
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Objects by name, type, or tag", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear object search")
                    }
                }
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                if objects.isEmpty {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "No Objects" : "No Matching Objects", systemImage: "square.stack")
                    } description: {
                        Text(search.isEmpty ? "Create an Object or register a file. Objects can appear in many Views." : "Try another name, type, or tag.")
                    } actions: {
                        if search.isEmpty {
                            Button("New Object") { editingObject = NauticaObject(type: "document", name: "") }
                            Button("Register File…") { registerFile(evidence: false) }
                        } else {
                            Button("Clear Search") { search = "" }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(objects) { object in
                        Button { editingObject = object } label: {
                            HStack {
                                Image(systemName: object.type == "audit" ? "checkmark.shield" : "doc")
                                VStack(alignment: .leading) {
                                    Text(object.name)
                                    Text("\(object.type) · \(object.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let status = object.metadata["status"] { Text(status).foregroundStyle(.secondary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Pin Object") { model.run { try await model.store.pin(.object, id: object.id.uuidString) } }
                            Menu("Add to Collection") {
                                ForEach(model.views.filter { $0.definition.kind == .collection }) { view in
                                    Button(view.name) {
                                        var updated = view
                                        if !updated.definition.memberIDs.contains(object.id) { updated.definition.memberIDs.append(object.id) }
                                        model.run { try await model.store.saveView(updated) }
                                    }
                                }
                            }
                            if let url = object.resourceURL { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        }
                    }
                }
                Divider()
                Text("\(objects.count) Objects · \(model.graph.relationships.count) Relationships")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { applyDestination() }
        .onChange(of: destination?.id) { _, _ in applyDestination() }
        .sheet(item: $editingObject) { GraphObjectEditor(model: model, original: $0) }
        .sheet(item: $editingView) { GraphViewBuilder(model: model, original: $0) }
        .sheet(isPresented: $showRelationship) { GraphRelationshipEditor(model: model) }
    }
    private func applyDestination() {
        selectedView = destination?.targetType == .view ? UUID(uuidString: destination!.targetID) : nil
        selectedObject = destination?.targetType == .object ? UUID(uuidString: destination!.targetID) : nil
    }
    private func registerFile(evidence: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !evidence
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        model.run { for url in urls { _ = try await model.store.registerFile(url, captureEvidence: evidence) } }
    }
}

struct GraphObjectEditor: View {
    @Bindable var model: GraphWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State var object: NauticaObject
    @State private var tags: String
    init(model: GraphWorkspaceModel, original: NauticaObject) {
        self.model = model
        _object = State(initialValue: original)
        _tags = State(initialValue: original.tags.joined(separator: ", "))
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("Object").font(.title2)
            Form {
                TextField("Name", text: $object.name)
                TextField("Type", text: $object.type)
                TextField("Tags (comma separated)", text: $tags)
                TextField("Status", text: Binding(get: { object.metadata["status"] ?? "" }, set: { object.metadata["status"] = $0 }))
                Picker("Priority", selection: Binding(get: { object.metadata["priority"] ?? "low" }, set: { object.metadata["priority"] = $0 })) {
                    ForEach(["low", "medium", "high", "critical"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Notes", text: Binding(get: { object.metadata["notes"] ?? "" }, set: { object.metadata["notes"] = $0 }), axis: .vertical)
                Picker("Lifecycle", selection: $object.lifecycle) { Text("Active").tag("active"); Text("Archived").tag("archived") }
            }
            Text("Relationships").font(.headline)
            ScrollView {
                ForEach(model.graph.relationships.filter { $0.sourceObjectID == object.id || $0.targetObjectID == object.id }) { edge in
                    let source = model.graph.objects.first { $0.id == edge.sourceObjectID }?.name ?? "Unknown"
                    let target = model.graph.objects.first { $0.id == edge.targetObjectID }?.name ?? "Unknown"
                    VStack(alignment: .leading) {
                        Text("\(source) → \(edge.type) → \(target)")
                        Text("\(edge.provenance.origin.rawValue) · \(edge.provenance.establishedBy) · \(edge.provenance.source)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                }
            }.frame(maxHeight: 140)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    object.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let value = object
                    model.run { try await model.store.saveObject(value); dismiss() }
                }.disabled(object.name.isEmpty || object.type.isEmpty || model.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600)
    }
}

struct GraphRelationshipEditor: View {
    @Bindable var model: GraphWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: UUID?
    @State private var target: UUID?
    @State private var type = "relatedTo"
    @State private var origin = RelationshipProvenance.Origin.userDefined
    @State private var provenance = "User assertion"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Relationship").font(.title2)
            objectPicker("From", selection: $source)
            TextField("Relationship type", text: $type)
            objectPicker("To", selection: $target)
            Picker("Origin", selection: $origin) {
                ForEach(RelationshipProvenance.Origin.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Source / provenance", text: $provenance)
            Text("Inferred relationships remain distinguishable and are excluded from traversal unless explicitly enabled.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    guard let source, let target else { return }
                    let edge = NauticaRelationship(type: type, sourceObjectID: source, targetObjectID: target, provenance: RelationshipProvenance(origin: origin, establishedBy: NSUserName(), source: provenance))
                    model.run { try await model.store.saveRelationship(edge); dismiss() }
                }.disabled(source == nil || target == nil || type.isEmpty || provenance.isEmpty || model.busy)
            }
        }.padding(24).frame(width: 520)
    }
    private func objectPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Choose Object").tag(UUID?.none)
            ForEach(model.graph.objects) { Text($0.name).tag(Optional($0.id)) }
        }
    }
}
