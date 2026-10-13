import SwiftUI

/// Floating HUD inspector for Finder-style "Show View Options" (⌘J).
/// Adjusts icon size, grid spacing, label position, text size, and column toggles in real time.
struct ViewOptionsView: View {
    let folderURL: URL
    @Binding var viewMode: ViewMode
    @Binding var iconSize: CGFloat
    @Binding var fontSize: CGFloat
    @Binding var groupBy: GroupByCriterion
    @Binding var labelOnBottom: Bool
    @Binding var showItemInfo: Bool

    // List view column toggles
    @Binding var showDateModified: Bool
    @Binding var showDateCreated: Bool
    @Binding var showSize: Bool
    @Binding var showKind: Bool
    @Binding var showTags: Bool

    let onUseAsDefaults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: folderURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folderURL.lastPathComponent.isEmpty ? "Macintosh HD" : folderURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text("View Options — \(viewMode.rawValue.capitalized) View")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()

            // View-specific settings
            if viewMode == .icon {
                iconViewSection
            } else if viewMode == .list {
                listViewSection
            } else {
                generalSection
            }

            Divider()

            // Group By / Arrange By section
            VStack(alignment: .leading, spacing: 6) {
                Text("Arrange By:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $groupBy) {
                    ForEach(GroupByCriterion.allCases) { criterion in
                        Text(criterion.title).tag(criterion)
                    }
                }
                .labelsHidden()
            }

            Divider()

            // Footer / Use as Defaults
            HStack {
                Button("Use as Defaults") {
                    onUseAsDefaults()
                }
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Icon View Section

    private var iconViewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Icon size:")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(iconSize)) × \(Int(iconSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $iconSize, in: 24...160, step: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Label position:")
                    .font(.caption)
                Picker("", selection: $labelOnBottom) {
                    Text("Bottom").tag(true)
                    Text("Right").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Text size:")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $fontSize, in: 10...16, step: 1)
            }

            Toggle("Show item info", isOn: $showItemInfo)
                .font(.caption)
        }
    }

    // MARK: - List View Section

    private var listViewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Text size:")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $fontSize, in: 10...16, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Icon size:")
                    .font(.caption)
                Picker("", selection: Binding(
                    get: { iconSize >= 24 ? 32 : 16 },
                    set: { iconSize = CGFloat($0) }
                )) {
                    Text("Small (16×16)").tag(16)
                    Text("Medium (32×32)").tag(32)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Show columns:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Date Modified", isOn: $showDateModified)
                    Toggle("Date Created", isOn: $showDateCreated)
                    Toggle("Size", isOn: $showSize)
                    Toggle("Kind", isOn: $showKind)
                    Toggle("Tags", isOn: $showTags)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adjust view parameters using View menu shortcuts.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
