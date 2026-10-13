import SwiftUI

/// Dialog for renaming multiple selected files using sequence, find & replace, or prefix/suffix patterns.
/// Shows a live side-by-side preview with conflicts highlighted in red (PRD F-012).
struct BatchRenameSheet: View {
    @State private var model: BatchRenameModel
    let onApply: ([(url: URL, newName: String)]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(items: [FileItem], onApply: @escaping ([(url: URL, newName: String)]) -> Void) {
        _model = State(initialValue: BatchRenameModel(items: items))
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Batch Rename")
                    .font(.headline)
                Spacer()
                Text("\(model.items.count) items selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Mode Selector
            Picker("Mode", selection: $model.mode) {
                ForEach(BatchRenameMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Mode Controls
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    switch model.mode {
                    case .format:
                        formatControls
                    case .findReplace:
                        findReplaceControls
                    case .addText:
                        addTextControls
                    case .changeCase:
                        changeCaseControls
                    }
                }
                .padding(6)
            }

            // Preview List
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Table(model.previewItems) {
                    TableColumn("Original Name") { item in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(item.originalName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    TableColumn("New Name") { item in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(item.newName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(item.hasConflict ? .red : (item.isChanged ? .primary : .secondary))

                            if let reason = item.conflictReason {
                                Spacer()
                                Label(reason, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 300)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            // Footer
            HStack {
                if model.hasConflicts {
                    Label("Resolve conflicts before renaming", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !model.canApply {
                    Text("No changes to apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    let renames = model.previewItems
                        .filter { $0.isChanged && !$0.hasConflict }
                        .map { ($0.originalURL, $0.newName) }
                    dismiss()
                    onApply(renames)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApply)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Mode Controls

    @ViewBuilder
    private var formatControls: some View {
        HStack(spacing: 12) {
            Text("Format:")
                .frame(width: 80, alignment: .trailing)
            Picker("Format Style", selection: $model.formatType) {
                ForEach(FormatType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
        }

        if model.formatType == .customPattern {
            HStack(spacing: 12) {
                Text("Pattern:")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g. vacation_###", text: $model.sequencePattern)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Tip: Use '#' for digit positions (e.g. vacation_### gives vacation_001)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 92)
        } else {
            HStack(spacing: 12) {
                Text("Custom Name:")
                    .frame(width: 80, alignment: .trailing)
                TextField("Name", text: $model.customFormatName)
                    .textFieldStyle(.roundedBorder)
            }
        }

        HStack(spacing: 12) {
            Text("Start at:")
                .frame(width: 80, alignment: .trailing)
            TextField("Start", value: $model.startIndex, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

            if model.formatType != .customPattern {
                Stepper("Digits: \(model.paddingDigits)", value: $model.paddingDigits, in: 1...6)
            }

            Spacer()
            Toggle("Keep extension", isOn: $model.keepExtension)
        }
    }

    @ViewBuilder
    private var findReplaceControls: some View {
        HStack(spacing: 12) {
            Text("Find:")
                .frame(width: 80, alignment: .trailing)
            TextField("Text to find", text: $model.findText)
                .textFieldStyle(.roundedBorder)
        }

        HStack(spacing: 12) {
            Text("Replace:")
                .frame(width: 80, alignment: .trailing)
            TextField("Replacement text", text: $model.replaceText)
                .textFieldStyle(.roundedBorder)
        }

        HStack(spacing: 16) {
            Spacer().frame(width: 80)
            Toggle("Match case", isOn: $model.caseSensitive)
            Toggle("Regular Expression", isOn: $model.useRegex)
            Spacer()
        }

        if model.useRegex {
            HStack {
                Spacer().frame(width: 80)
                Text("Supports regex capture groups in replace (e.g. $1, $2)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let error = model.regexError {
                HStack {
                    Spacer().frame(width: 80)
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var addTextControls: some View {
        HStack(spacing: 12) {
            Text("Add:")
                .frame(width: 80, alignment: .trailing)
            TextField("Text to add", text: $model.addTextString)
                .textFieldStyle(.roundedBorder)
            Picker("Position", selection: $model.addTextPosition) {
                ForEach(AddTextPosition.allCases) { pos in
                    Text(pos.rawValue).tag(pos)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }
    }

    @ViewBuilder
    private var changeCaseControls: some View {
        HStack(spacing: 12) {
            Text("Case:")
                .frame(width: 80, alignment: .trailing)
            Picker("Case Style", selection: $model.caseTarget) {
                ForEach(CaseTarget.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
        }

        HStack {
            Spacer().frame(width: 80)
            Toggle("Apply to extension", isOn: $model.applyToExtension)
            Spacer()
        }
    }
}
