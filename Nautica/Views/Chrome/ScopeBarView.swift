import SwiftUI

/// Finder-style Scope Bar displayed under the toolbar during an active search.
/// Provides instant toggling between "This Mac" and the current folder scope,
/// switching between filename-only and full-content matching, result counts,
/// and saving search queries as macOS Smart Folders.
struct ScopeBarView: View {
    let currentFolderURL: URL
    let resultCount: Int
    let isGathering: Bool
    var isTruncated: Bool = false
    var totalCount: Int = 0
    @Binding var scope: SearchScope
    @Binding var filter: SearchFilter
    @Binding var criteria: [SearchCriterion]
    let onCriteriaChanged: () -> Void
    let onSaveSmartFolder: (String) -> Void
    let onDismissSearch: () -> Void

    @State private var isShowingSaveSheet = false
    @State private var smartFolderName = ""
    @State private var isCriteriaExpanded = false

    private var currentFolderName: String {
        let name = currentFolderURL.lastPathComponent
        return name.isEmpty ? "Current Folder" : name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Scope Bar Row
            HStack(spacing: 12) {
                Text("Search:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                // Scope toggle: This Mac vs Current Folder
                Picker("", selection: $scope) {
                    Text("This Mac").tag(SearchScope.localComputer)
                    Text("\"\(currentFolderName)\"").tag(SearchScope.folder(currentFolderURL))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                // Filter toggle: Name Matches vs Name and Content
                Picker("", selection: $filter) {
                    Text("Name").tag(SearchFilter.nameOnly)
                    Text("Name & Content").tag(SearchFilter.nameAndContent)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if isGathering {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }

                if isTruncated {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Showing 500 of \(totalCount) items (capped)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    Text("\(resultCount) \(resultCount == 1 ? "item" : "items")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    smartFolderName = "Search \(currentFolderName)"
                    isShowingSaveSheet = true
                }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Save as Smart Folder")

                Button(action: {
                    isCriteriaExpanded.toggle()
                    if isCriteriaExpanded && criteria.isEmpty {
                        criteria.append(SearchCriterion())
                        onCriteriaChanged()
                    }
                }) {
                    Image(systemName: (isCriteriaExpanded || !criteria.isEmpty) ? "plus.circle.fill" : "plus.circle")
                        .font(.system(size: 13))
                        .foregroundColor((isCriteriaExpanded || !criteria.isEmpty) ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isCriteriaExpanded ? "Hide Criteria Rules" : "Add Search Criteria Rules")

                Button(action: onDismissSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Criteria Builder Rows
            if isCriteriaExpanded || !criteria.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach($criteria) { $criterion in
                        criterionRow(criterion: $criterion)
                    }
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .onChange(of: criteria) { _, _ in
            onCriteriaChanged()
        }
        .sheet(isPresented: $isShowingSaveSheet) {
            VStack(spacing: 16) {
                Text("Save Smart Folder")
                    .font(.headline)

                TextField("Name", text: $smartFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                HStack {
                    Button("Cancel") {
                        isShowingSaveSheet = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        isShowingSaveSheet = false
                        if !smartFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                            onSaveSmartFolder(smartFolderName)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    // MARK: - Criterion Row

    @ViewBuilder
    private func criterionRow(criterion: Binding<SearchCriterion>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: criterion.attribute) {
                ForEach(SearchCriterionAttribute.allCases) { attr in
                    Text(attr.rawValue).tag(attr)
                }
            }
            .labelsHidden()
            .fixedSize()

            switch criterion.wrappedValue.attribute {
            case .kind:
                Picker("", selection: criterion.kind) {
                    ForEach(KindOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .labelsHidden()
                .fixedSize()

            case .dateModified, .dateCreated:
                Picker("", selection: criterion.dateOption) {
                    ForEach(DateOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .labelsHidden()
                .fixedSize()

            case .fileSize:
                Picker("", selection: criterion.sizeComparison) {
                    ForEach(SizeComparison.allCases) { comp in
                        Text(comp.rawValue).tag(comp)
                    }
                }
                .labelsHidden()
                .fixedSize()

                TextField("Size", value: criterion.sizeValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)

                Picker("", selection: criterion.sizeUnit) {
                    ForEach(SizeUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()

            case .name:
                Picker("", selection: criterion.nameComparison) {
                    ForEach(NameComparison.allCases) { comp in
                        Text(comp.rawValue).tag(comp)
                    }
                }
                .labelsHidden()
                .fixedSize()

                TextField("Name", text: criterion.textValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)

            case .tags:
                TextField("Tag name", text: criterion.tagValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Spacer()

            Button(action: {
                criteria.append(SearchCriterion())
                onCriteriaChanged()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add Search Criterion")

            Button(action: {
                criteria.removeAll { $0.id == criterion.wrappedValue.id }
                onCriteriaChanged()
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove This Criterion")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}
