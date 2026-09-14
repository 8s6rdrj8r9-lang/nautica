import Foundation

/// Defines the strategy used to compute new names for a collection of files.
enum BatchRenameMode: String, CaseIterable, Identifiable {
    case sequence = "Sequence"
    case findReplace = "Find & Replace"
    case addText = "Add Text"

    var id: String { rawValue }
}

/// Preview of a single item's proposed rename state.
struct BatchRenamePreviewItem: Identifiable, Equatable {
    let id: UUID
    let originalURL: URL
    let originalName: String
    var newName: String
    var conflictReason: String?

    var hasConflict: Bool { conflictReason != nil }
    var isChanged: Bool { originalName != newName }
}

/// Computes batch rename previews and validates against collisions and illegal characters.
@Observable
final class BatchRenameModel {
    var mode: BatchRenameMode = .sequence

    // MARK: - Sequence Mode Options
    /// Pattern supporting '#' placeholders (e.g. "vacation_###.jpg" or "photo_").
    var sequencePattern: String = "file_###"
    var startIndex: Int = 1
    var paddingDigits: Int = 3
    var keepExtension: Bool = true

    // MARK: - Find & Replace Options
    var findText: String = ""
    var replaceText: String = ""
    var caseSensitive: Bool = false

    // MARK: - Add Text Options
    var prefixText: String = ""
    var suffixText: String = ""

    let items: [FileItem]

    init(items: [FileItem]) {
        self.items = items
        if let first = items.first {
            let ext = first.url.pathExtension
            if !ext.isEmpty {
                sequencePattern = "item_###.\(ext)"
            }
        }
    }

    /// Computes the live preview for each item, checking for conflicts and duplicates.
    var previewItems: [BatchRenamePreviewItem] {
        var results: [BatchRenamePreviewItem] = []
        var proposedNamesCount: [String: Int] = [:]

        // 1. Generate proposed names
        for (index, item) in items.enumerated() {
            let currentNumber = startIndex + index
            let newName = computeNewName(for: item, number: currentNumber)
            results.append(BatchRenamePreviewItem(
                id: item.id,
                originalURL: item.url,
                originalName: item.name,
                newName: newName,
                conflictReason: nil
            ))
            proposedNamesCount[newName, default: 0] += 1
        }

        // 2. Validate names, collisions, and filesystem status
        let parentDirectory = items.first?.url.deletingLastPathComponent()
        let existingOriginalNames = Set(items.map(\.name))

        for i in 0..<results.count {
            let newName = results[i].newName
            let originalName = results[i].originalName

            if newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results[i].conflictReason = "Name cannot be empty"
            } else if newName.contains("/") || newName.contains(":") {
                results[i].conflictReason = "Cannot contain '/' or ':'"
            } else if (proposedNamesCount[newName] ?? 0) > 1 {
                results[i].conflictReason = "Duplicate new name"
            } else if newName != originalName, let parentDirectory {
                let targetURL = parentDirectory.appendingPathComponent(newName)
                if FileManager.default.fileExists(atPath: targetURL.path) && !existingOriginalNames.contains(newName) {
                    results[i].conflictReason = "File already exists"
                }
            }
        }

        return results
    }

    var hasConflicts: Bool {
        previewItems.contains { $0.hasConflict }
    }

    var canApply: Bool {
        !hasConflicts && previewItems.contains { $0.isChanged }
    }

    // MARK: - Private Computation

    private func computeNewName(for item: FileItem, number: Int) -> String {
        let original = item.name
        let ext = item.url.pathExtension
        let baseName = (original as NSString).deletingPathExtension

        switch mode {
        case .sequence:
            return computeSequenceName(original: original, baseName: baseName, ext: ext, number: number)

        case .findReplace:
            guard !findText.isEmpty else { return original }
            if caseSensitive {
                return original.replacingOccurrences(of: findText, with: replaceText)
            } else {
                return original.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
            }

        case .addText:
            var result = baseName
            if !prefixText.isEmpty {
                result = prefixText + result
            }
            if !suffixText.isEmpty {
                result = result + suffixText
            }
            if !ext.isEmpty {
                result = result + "." + ext
            }
            return result
        }
    }

    private func computeSequenceName(original: String, baseName: String, ext: String, number: Int) -> String {
        let pattern = sequencePattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return original }

        // If the pattern contains '#' placeholders (e.g. vacation_###.jpg)
        if let firstHash = pattern.firstIndex(of: "#") {
            let hashes = pattern[firstHash...].prefix(while: { $0 == "#" })
            let hashCount = hashes.count
            let hashEnd = pattern.index(firstHash, offsetBy: hashCount)
            let numberString = String(format: "%0*d", hashCount, number)
            var formatted = pattern
            formatted.replaceSubrange(firstHash..<hashEnd, with: numberString)
            return formatted
        }

        // Otherwise append the number to the pattern
        let numberString = String(format: "%0*d", max(1, paddingDigits), number)
        var result = pattern + numberString
        if keepExtension && !ext.isEmpty && !pattern.hasSuffix("." + ext) {
            result += "." + ext
        }
        return result
    }
}
