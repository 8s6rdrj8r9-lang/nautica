import SwiftUI

/// Instant in-folder filter strip for real-time item filtering (ForkLift / Path Finder style).
/// Allows filtering the current directory by filename substring, extension, and color tag.
struct FilterBarView: View {
    @Bindable var directoryContents: DirectoryContents
    let onDismiss: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(directoryContents.isFiltering ? Color.accentColor : .secondary)

            // Text search input
            HStack(spacing: 4) {
                TextField("Filter files…", text: $directoryContents.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFieldFocused)

                if !directoryContents.filterText.isEmpty {
                    Button {
                        directoryContents.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .frame(minWidth: 140, idealWidth: 200, maxWidth: 260)

            // Tag color filters
            HStack(spacing: 5) {
                // All pill
                Button {
                    directoryContents.filterTag = nil
                } label: {
                    Text("All")
                        .font(.system(size: 11, weight: directoryContents.filterTag == nil ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(directoryContents.filterTag == nil ? Color.accentColor.opacity(0.18) : Color.clear)
                        .foregroundStyle(directoryContents.filterTag == nil ? Color.accentColor : .secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // 7 color dots
                ForEach(TagColor.allCases) { color in
                    let isSelected = directoryContents.filterTag == color
                    Button {
                        if isSelected {
                            directoryContents.filterTag = nil
                        } else {
                            directoryContents.filterTag = color
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 12, height: 12)

                            if isSelected {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1.5)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Filter by \(color.name) (^\(color.shortcutNumber))")
                }
            }
            .padding(.leading, 4)

            Spacer()

            // Count badge
            if directoryContents.isFiltering {
                Text("\(directoryContents.items.count) of \(directoryContents.totalUnfilteredCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Close button
            Button {
                directoryContents.clearFilter()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Filter Bar (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onAppear {
            isFieldFocused = true
        }
        .onExitCommand {
            directoryContents.clearFilter()
            onDismiss()
        }
    }
}
