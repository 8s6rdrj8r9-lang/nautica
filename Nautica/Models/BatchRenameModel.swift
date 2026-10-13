import Foundation

/// Defines the strategy used to compute new names for a collection of files.
enum BatchRenameMode: String, CaseIterable, Identifiable {
    case format = "Format"
    case findReplace = "Find & Replace"
    case addText = "Add Text"
    case changeCase = "Change Case"

    // Backward-compatibility alias for Phase 1 tests
    static var sequence: BatchRenameMode { .format }

    var id: String { rawValue }
}

/// Format style for sequential / counter numbering.
enum FormatType: String, CaseIterable, Identifiable {
    case nameAndCounter = "Name and Counter"
    case counterAndName = "Counter and Name"
    case customPattern = "Custom Pattern (#)"

    var id: String { rawValue }
}

/// Where to add text in Add Text mode.
enum AddTextPosition: String, CaseIterable, Identifiable {
    case beforeName = "Before Name"
    case afterName = "After Name"

    var id: String { rawValue }
}

/// Target casing for Change Case mode.
enum CaseTarget: String, CaseIterable, Identifiable {
    case lowercase = "all lowercase"
    case uppercase = "ALL UPPERCASE"
    case titleCase = "Title Case"
    case sentenceCase = "Sentence case"

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
    var mode: BatchRenameMode = .format

    // MARK: - Format / Counter Options
    var formatType: FormatType = .nameAndCounter
    var customFormatName: String = ""
    var sequencePattern: String = "file_###"
    var startIndex: Int = 1
    var paddingDigits: Int = 3
    var keepExtension: Bool = true

    // MARK: - Find & Replace Options
    var findText: String = ""
    var replaceText: String = ""
    var caseSensitive: Bool = false
    var useRegex: Bool = false

    // MARK: - Add Text Options
    var addTextPosition: AddTextPosition = .beforeName
    var addTextString: String = ""
    var prefixText: String = ""
    var suffixText: String = ""

    // MARK: - Change Case Options
    var caseTarget: CaseTarget = .lowercase
    var applyToExtension: Bool = false

    let items: [FileItem]

    init(items: [FileItem]) {
        self.items = items
        if let first = items.first {
            let ext = first.url.pathExtension
            let base = (first.name as NSString).deletingPathExtension
            customFormatName = base
            if !ext.isEmpty {
                sequencePattern = "item_###.\(ext)"
            }
        }
    }

    /// Returns non-nil if regular expression syntax is malformed.
    var regexError: String? {
        guard mode == .findReplace && useRegex && !findText.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: findText, options: caseSensitive ? [] : [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
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

            if let regexErr = regexError {
                results[i].conflictReason = "Regex: \(regexErr)"
            } else if newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        !hasConflicts && regexError == nil && previewItems.contains { $0.isChanged }
    }

    // MARK: - Private Computation

    private func computeNewName(for item: FileItem, number: Int) -> String {
        let original = item.name
        let ext = item.url.pathExtension
        let baseName = (original as NSString).deletingPathExtension

        switch mode {
        case .format:
            return computeFormatName(original: original, baseName: baseName, ext: ext, number: number)

        case .findReplace:
            guard !findText.isEmpty else { return original }
            if useRegex {
                do {
                    let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
                    let regex = try NSRegularExpression(pattern: findText, options: options)
                    let range = NSRange(original.startIndex..<original.endIndex, in: original)
                    return regex.stringByReplacingMatches(in: original, options: [], range: range, withTemplate: replaceText)
                } catch {
                    return original
                }
            } else {
                if caseSensitive {
                    return original.replacingOccurrences(of: findText, with: replaceText)
                } else {
                    return original.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
                }
            }

        case .addText:
            var result = baseName
            // Handle both legacy prefix/suffix and new addText controls
            if !prefixText.isEmpty { result = prefixText + result }
            if !suffixText.isEmpty { result = result + suffixText }

            if !addTextString.isEmpty {
                switch addTextPosition {
                case .beforeName:
                    result = addTextString + result
                case .afterName:
                    result = result + addTextString
                }
            }

            if !ext.isEmpty {
                result = result + "." + ext
            }
            return result

        case .changeCase:
            let transformedBase: String
            switch caseTarget {
            case .lowercase:
                transformedBase = baseName.lowercased()
            case .uppercase:
                transformedBase = baseName.uppercased()
            case .titleCase:
                transformedBase = baseName.capitalized
            case .sentenceCase:
                transformedBase = Self.toSentenceCase(baseName)
            }

            var finalExt = ext
            if applyToExtension && !ext.isEmpty {
                switch caseTarget {
                case .lowercase: finalExt = ext.lowercased()
                case .uppercase: finalExt = ext.uppercased()
                case .titleCase: finalExt = ext.capitalized
                case .sentenceCase: finalExt = ext.lowercased()
                }
            }

            return finalExt.isEmpty ? transformedBase : "\(transformedBase).\(finalExt)"
        }
    }

    private func computeFormatName(original: String, baseName: String, ext: String, number: Int) -> String {
        // If sequence pattern has '#' placeholders, respect it
        if sequencePattern.contains("#") {
            return computeSequenceWithHashes(original: original, pattern: sequencePattern, number: number)
        }

        let numStr = String(format: "%0*d", max(1, paddingDigits), number)
        let patternName = sequencePattern.trimmingCharacters(in: .whitespaces)
        let customName = customFormatName.trimmingCharacters(in: .whitespaces)
        let name = (!patternName.isEmpty && patternName != "file_###" && !patternName.hasPrefix("item_###")) ? patternName : customName

        var result: String
        switch formatType {
        case .nameAndCounter:
            if name.isEmpty {
                result = numStr
            } else if name.hasSuffix("_") || name.hasSuffix("-") || name.hasSuffix(" ") {
                result = "\(name)\(numStr)"
            } else {
                result = "\(name)_\(numStr)"
            }
        case .counterAndName:
            if name.isEmpty {
                result = numStr
            } else if name.hasPrefix("_") || name.hasPrefix("-") || name.hasPrefix(" ") {
                result = "\(numStr)\(name)"
            } else {
                result = "\(numStr)_\(name)"
            }
        case .customPattern:
            return computeSequenceWithHashes(original: original, pattern: sequencePattern, number: number)
        }

        if keepExtension && !ext.isEmpty {
            result += ".\(ext)"
        }
        return result
    }

    private func computeSequenceWithHashes(original: String, pattern: String, number: Int) -> String {
        guard let firstHash = pattern.firstIndex(of: "#") else { return original }
        let hashes = pattern[firstHash...].prefix(while: { $0 == "#" })
        let hashCount = hashes.count
        let hashEnd = pattern.index(firstHash, offsetBy: hashCount)
        let numberString = String(format: "%0*d", hashCount, number)
        var formatted = pattern
        formatted.replaceSubrange(firstHash..<hashEnd, with: numberString)
        return formatted
    }

    static func toSentenceCase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let lower = text.lowercased()
        let first = lower.prefix(1).uppercased()
        let rest = lower.dropFirst()
        return first + rest
    }
}
