import SwiftUI
import AppKit

/// Reusable right-sidebar inspector component providing a 7-color Finder label palette,
/// removable tag chips, and instant custom tag creation with batch selection support.
struct TagPaletteView: View {
    let selectedItems: [FileItem]
    var onReloadDirectory: (() -> Void)? = nil

    @State private var newTagName: String = ""
    @State private var hoveredTag: String? = nil

    private var uniqueTags: [FileTagInfo] {
        var seen = Set<String>()
        var result: [FileTagInfo] = []
        for item in selectedItems {
            for tag in item.tagInfos {
                let key = tag.displayName.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(tag)
                }
            }
        }
        return result
    }

    private func isColorActive(_ color: TagColor) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { $0.tagColors.contains(color) }
    }

    private func isColorPartial(_ color: TagColor) -> Bool {
        let count = selectedItems.filter { $0.tagColors.contains(color) }.count
        return count > 0 && count < selectedItems.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header
            HStack {
                Label("Tags & Color Labels", systemImage: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !uniqueTags.isEmpty {
                    Button(action: clearAllTags) {
                        Text("Clear All")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove all tags from selection")
                }
            }

            // 7 macOS Color Circles
            HStack(spacing: 7) {
                ForEach(TagColor.allCases) { color in
                    Button {
                        toggleColor(color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 18, height: 18)
                                .shadow(color: color.color.opacity(0.3), radius: 1.5, x: 0, y: 1)

                            if isColorActive(color) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if isColorPartial(color) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(isColorActive(color) ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                        )
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("\(color.name) (⌃\(color.shortcutNumber)) — Click to toggle")
                }
            }
            .padding(.vertical, 2)

            // Active Tag Chips
            if !uniqueTags.isEmpty {
                TagFlowLayout(spacing: 4) {
                    ForEach(uniqueTags) { tag in
                        HStack(spacing: 4) {
                            if let col = tag.color {
                                Circle()
                                    .fill(col.color)
                                    .frame(width: 7, height: 7)
                            }

                            Text(tag.displayName)
                                .font(.system(size: 11))
                                .lineLimit(1)

                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(tag.color?.color.opacity(0.15) ?? Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(tag.color?.color.opacity(0.35) ?? Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                    }
                }
            }

            // Add Tag Field
            HStack(spacing: 6) {
                TextField("Add tag…", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit {
                        addNewTag()
                    }

                Button(action: addNewTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add Tag (Return)")
            }
        }
    }

    // MARK: - Actions

    private func toggleColor(_ color: TagColor) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            try? await TagService.shared.toggleColorTag(color, for: urls)
            await MainActor.run {
                onReloadDirectory?()
            }
        }
    }

    private func removeTag(_ tag: FileTagInfo) {
        let targetName = tag.displayName.lowercased()
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                let values = (try? url.resourceValues(forKeys: [.tagNamesKey])) ?? URLResourceValues()
                var currentTags = values.tagNames ?? []
                currentTags.removeAll { FileTagInfo(rawName: $0).displayName.lowercased() == targetName }
                try? (url as NSURL).setResourceValue(currentTags as NSArray, forKey: .tagNamesKey)
            }
            await MainActor.run {
                onReloadDirectory?()
            }
        }
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        newTagName = ""

        Task {
            for url in urls {
                let values = (try? url.resourceValues(forKeys: [.tagNamesKey])) ?? URLResourceValues()
                var currentTags = values.tagNames ?? []
                let alreadyPresent = currentTags.contains {
                    FileTagInfo(rawName: $0).displayName.lowercased() == trimmed.lowercased()
                }
                if !alreadyPresent {
                    if let color = TagColor.from(name: trimmed) {
                        currentTags.append("\(color.name)\n\(color.rawValue)")
                    } else {
                        currentTags.append(trimmed)
                    }
                    try? (url as NSURL).setResourceValue(currentTags as NSArray, forKey: .tagNamesKey)
                }
            }
            await MainActor.run {
                onReloadDirectory?()
            }
        }
    }

    private func clearAllTags() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            try? await TagService.shared.clearAllTags(for: urls)
            await MainActor.run {
                onReloadDirectory?()
            }
        }
    }
}

/// Simple flow layout to arrange tag chips dynamically horizontally and wrap to new lines.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 200
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        height = currentY + rowHeight
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
