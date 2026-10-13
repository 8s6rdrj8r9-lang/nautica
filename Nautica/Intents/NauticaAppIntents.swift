import AppIntents
import Foundation

// MARK: - Path & File Resolver

enum IntentPathResolver {
    static func resolveURL(file: IntentFile?, path: String?, defaultFolder: String = "Desktop") -> URL? {
        if let file = file, let url = file.fileURL {
            return url
        }
        guard let path = path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FileManager.default.homeURL.appendingPathComponent(defaultFolder)
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "home":
            return FileManager.default.homeURL
        case "desktop":
            return FileManager.default.homeURL.appendingPathComponent("Desktop")
        case "downloads":
            return FileManager.default.homeURL.appendingPathComponent("Downloads")
        case "documents":
            return FileManager.default.homeURL.appendingPathComponent("Documents")
        default:
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
    }
}

// MARK: - Summarize Directory Intent

public struct SummarizeDirectoryIntent: AppIntent {
    public static var title: LocalizedStringResource = "Summarize Directory in Nautica"
    public static var description = IntentDescription("Generates an on-device summary of files and subdirectories using Apple Foundation Models.")

    @Parameter(title: "Target Folder", description: "Folder path or shortcut name (e.g., Desktop, Downloads)", default: "Desktop")
    public var folderName: String?

    @Parameter(title: "Folder File", description: "Direct file reference from Finder or Shortcuts", default: nil)
    public var folderFile: IntentFile?

    public static var parameterSummary: some ParameterSummary {
        Summary("Summarize folder \(\.$folderName) in Nautica")
    }

    public init() {}

    public init(folderName: String? = "Desktop", folderFile: IntentFile? = nil) {
        self.folderName = folderName
        self.folderFile = folderFile
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = IntentPathResolver.resolveURL(file: folderFile, path: folderName, defaultFolder: "Desktop") else {
            return .result(dialog: "Could not find folder.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .result(dialog: "Folder does not exist at \(url.lastPathComponent).")
        }

        let summary = try await AIService.shared.summarizeDirectory(at: url)
        return .result(dialog: "\(summary)")
    }
}

// MARK: - Tag Files Intent

public struct TagFilesIntent: AppIntent {
    public static var title: LocalizedStringResource = "Suggest Tags with Nautica AI"
    public static var description = IntentDescription("Generates recommended organization tags for a file using on-device intelligence.")

    @Parameter(title: "File Path", description: "Path or document name", default: nil)
    public var filePath: String?

    @Parameter(title: "File", description: "File reference to inspect", default: nil)
    public var file: IntentFile?

    public static var parameterSummary: some ParameterSummary {
        Summary("Suggest tags for \(\.$filePath) in Nautica")
    }

    public init() {}

    public init(filePath: String? = nil, file: IntentFile? = nil) {
        self.filePath = filePath
        self.file = file
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = IntentPathResolver.resolveURL(file: file, path: filePath, defaultFolder: "Downloads") else {
            return .result(dialog: "No file specified.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .result(dialog: "File not found: \(url.lastPathComponent)")
        }

        let tags = try await AIService.shared.suggestTags(for: url)
        let tagString = tags.joined(separator: ", ")
        return .result(dialog: "Suggested tags for \(url.lastPathComponent): \(tagString)")
    }
}

// MARK: - Explain File Intent

public struct ExplainFileIntent: AppIntent {
    public static var title: LocalizedStringResource = "Explain File in Nautica"
    public static var description = IntentDescription("Explains the content and purpose of a document or code file in Nautica.")

    @Parameter(title: "File Path", description: "Path or document name", default: nil)
    public var filePath: String?

    @Parameter(title: "File", description: "File reference to analyze", default: nil)
    public var file: IntentFile?

    public static var parameterSummary: some ParameterSummary {
        Summary("Explain file \(\.$filePath) in Nautica")
    }

    public init() {}

    public init(filePath: String? = nil, file: IntentFile? = nil) {
        self.filePath = filePath
        self.file = file
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = IntentPathResolver.resolveURL(file: file, path: filePath, defaultFolder: "Documents") else {
            return .result(dialog: "No document specified.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .result(dialog: "File not found: \(url.lastPathComponent)")
        }

        let explanation = try await AIService.shared.explainFile(at: url)
        return .result(dialog: "\(explanation)")
    }
}

// MARK: - App Shortcuts Provider for macOS 27 Siri AI & Spotlight

public struct NauticaShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor = .navy

    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SummarizeDirectoryIntent(),
            phrases: [
                "Summarize folder \(\.$folderName) in \(.applicationName)",
                "Summarize my \(\.$folderName) in \(.applicationName)",
                "What is inside \(\.$folderName) in \(.applicationName)"
            ],
            shortTitle: "Summarize Folder",
            systemImageName: "folder.badge.gearshape"
        )
        AppShortcut(
            intent: TagFilesIntent(),
            phrases: [
                "Suggest tags for \(\.$filePath) in \(.applicationName)",
                "Tag \(\.$filePath) with \(.applicationName)",
                "Organize \(\.$filePath) in \(.applicationName)"
            ],
            shortTitle: "Suggest Tags",
            systemImageName: "tag.fill"
        )
        AppShortcut(
            intent: ExplainFileIntent(),
            phrases: [
                "Explain file \(\.$filePath) in \(.applicationName)",
                "What does \(\.$filePath) do in \(.applicationName)"
            ],
            shortTitle: "Explain File",
            systemImageName: "doc.text.magnifyingglass"
        )
    }
}
