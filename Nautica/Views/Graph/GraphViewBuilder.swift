import SwiftUI

struct GraphViewBuilder: View {
    @Bindable var model: GraphWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var view: NauticaView
    @State private var pin = true
    @State private var scoped = false
    @State private var start: UUID?
    @State private var types = ""
    @State private var objectTypes = ""
    @State private var direction = GraphTraversal.Direction.both
    @State private var depth = 4
    @State private var includeInferred = false
    @State private var includeStart = true
    @State private var search = ""
    init(model: GraphWorkspaceModel, original: NauticaView) {
        self.model = model
        _view = State(initialValue: original)
        _pin = State(initialValue: !model.views.contains { $0.id == original.id } || model.pins.contains { $0.targetType == .view && $0.targetID == original.id.uuidString })
        if let traversal = original.definition.traversal {
            _scoped = State(initialValue: true)
            _start = State(initialValue: traversal.startObjectID)
            _types = State(initialValue: traversal.relationshipTypes.joined(separator: ", "))
            _objectTypes = State(initialValue: traversal.objectTypes.joined(separator: ", "))
            _direction = State(initialValue: traversal.direction)
            _depth = State(initialValue: traversal.maxDepth)
            _includeInferred = State(initialValue: traversal.includeInferred)
            _includeStart = State(initialValue: traversal.includeStart)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.views.contains { $0.id == view.id } ? "Configure View" : "New View").font(.title2)
            TextField("Name", text: $view.name)
            Picker("Type", selection: $view.definition.kind) {
                ForEach(GraphViewDefinition.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Explicit membership").font(.headline)
                    TextField("Find Objects", text: $search)
                    ForEach(model.graph.objects.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { object in
                        Toggle(object.name, isOn: Binding(get: { view.definition.memberIDs.contains(object.id) }, set: { include in
                            view.definition.memberIDs.removeAll { $0 == object.id }
                            if include { view.definition.memberIDs.append(object.id) }
                        }))
                    }
                    Divider()
                    HStack {
                        Text("Rules (all must match)").font(.headline)
                        Spacer()
                        Button("Add Rule") { view.definition.filters.append(GraphFilter(field: "status", value: "open")) }
                    }
                    ForEach(view.definition.filters.indices, id: \.self) { index in
                        HStack {
                            TextField("Property / type / tag", text: $view.definition.filters[index].field)
                            Picker("Operator", selection: $view.definition.filters[index].comparison) {
                                ForEach(GraphFilter.Comparison.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 110)
                            TextField("Value", text: $view.definition.filters[index].value)
                            Button("Remove", systemImage: "minus.circle") { view.definition.filters.remove(at: index) }.labelStyle(.iconOnly)
                        }
                    }
                    Divider()
                    Toggle("Relationship scope", isOn: $scoped).disabled(view.definition.kind == .relationship)
                    if scoped || view.definition.kind == .relationship {
                        Picker("Starting Object", selection: $start) {
                            Text("Choose Object").tag(UUID?.none)
                            ForEach(model.graph.objects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        TextField("Relationship types (comma separated; empty = all)", text: $types)
                        TextField("Result types (e.g. requirement, evidence, audit, finding, verification)", text: $objectTypes)
                        Picker("Direction", selection: $direction) { ForEach(GraphTraversal.Direction.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Stepper("Maximum depth: \(depth)", value: $depth, in: 1...16)
                        Toggle("Include starting Object", isOn: $includeStart)
                        Toggle("Include inferred relationships", isOn: $includeInferred)
                    }
                    Toggle("Include archived Objects", isOn: $view.definition.includesArchived)
                }.padding(4)
            }
            Toggle("Pin to Right Dock", isOn: $pin)
            Text("Views do not own Objects. Deleting a View leaves its Objects intact.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save View") {
                    if (scoped || view.definition.kind == .relationship), let start {
                        view.definition.traversal = GraphTraversal(startObjectID: start, relationshipTypes: split(types), objectTypes: split(objectTypes), direction: direction, maxDepth: depth, includeStart: includeStart, includeInferred: includeInferred)
                    } else { view.definition.traversal = nil }
                    let updated = view
                    let shouldPin = pin
                    model.run {
                        try await model.store.saveView(updated)
                        if shouldPin { try await model.store.pin(.view, id: updated.id.uuidString) }
                        else { for existing in model.pins where existing.targetType == .view && existing.targetID == updated.id.uuidString { try await model.store.removePin(existing.id) } }
                        dismiss()
                    }
                }.disabled(view.name.trimmingCharacters(in: .whitespaces).isEmpty || ((scoped || view.definition.kind == .relationship) && start == nil) || model.busy)
                .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 660, height: 650)
    }
    private func split(_ value: String) -> [String] { value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct RightDockSettingsView: View {
    @State private var model = GraphWorkspaceModel.shared
    @AppStorage("Nautica.RightDock.Enabled") private var enabled = true
    @AppStorage("Nautica.RightDock.Labels") private var labels = true
    @AppStorage("Nautica.RightDock.Compact") private var compact = false
    @State private var editing: NauticaView?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Right Dock", isOn: $enabled)
            Toggle("Show Labels", isOn: $labels)
            Picker("Presentation", selection: $compact) { Text("Expanded").tag(false); Text("Compact").tag(true) }
            HStack {
                Button("Add View") { editing = NauticaView(name: "") }
                Menu("Pin Existing View") {
                    ForEach(model.views) { view in Button(view.name) { model.run { try await model.store.pin(.view, id: view.id.uuidString) } } }
                }
                Menu("Pin Subsystem") {
                    ForEach(SubsystemRegistry.all) { subsystem in Button(subsystem.name) { model.run { try await model.store.pin(.subsystem, id: subsystem.id) } } }
                }
            }
            HStack {
                Menu("Pin Object") {
                    ForEach(model.graph.objects) { object in Button(object.name) { model.run { try await model.store.pin(.object, id: object.id.uuidString) } } }
                }
                Button("Pin New View Action") { model.run { try await model.store.pin(.action, id: "newView") } }
            }
            List {
                ForEach(Array(model.pins.enumerated()), id: \.element.id) { index, pin in
                    HStack {
                        Label(model.label(pin), systemImage: model.symbol(pin))
                        Spacer()
                        if pin.targetType == .view, let view = model.views.first(where: { $0.id.uuidString == pin.targetID }) {
                            Button("Configure") { editing = view }
                        }
                        Button("Move up", systemImage: "arrow.up") { move(index, -1) }.labelStyle(.iconOnly).disabled(index == 0)
                        Button("Move down", systemImage: "arrow.down") { move(index, 1) }.labelStyle(.iconOnly).disabled(index == model.pins.count - 1)
                        Button("Remove from Dock", systemImage: "minus.circle") { model.run { try await model.store.removePin(pin.id) } }.labelStyle(.iconOnly)
                    }.buttonStyle(.borderless).accessibilityElement(children: .contain)
                }
            }
            Text("Removing a pin leaves its View, Object, or Subsystem intact.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        .task { do { try await model.refresh() } catch { model.error = error.localizedDescription } }
        .sheet(item: $editing) { GraphViewBuilder(model: model, original: $0) }
        .alert("Nautica", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func move(_ index: Int, _ delta: Int) {
        var ids = model.pins.map(\.id)
        ids.swapAt(index, index + delta)
        model.run { try await model.store.reorderPins(ids) }
    }
}
