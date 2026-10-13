import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Central Intelligence service for Nautica on macOS 27.
/// Defaults to on-device Apple Foundation Models (zero network, zero cost, completely private),
/// with optional opt-in ChatGPT (OpenAI) backup for complex multi-file reasoning.
public actor AIService {
    public static let shared = AIService()

    public enum Provider: String, CaseIterable, Sendable {
        case appleFoundation = "appleFoundation"
        case openAI = "openAI"

        public var displayName: String {
            switch self {
            case .appleFoundation: return "Apple Foundation Models (On-Device)"
            case .openAI:          return "ChatGPT (OpenAI Backup)"
            }
        }
    }

    private init() {}

    // MARK: - Status

    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return true
    }

    // MARK: - Directory Summarization

    /// Generates a concise natural language summary of a directory's contents.
    public func summarizeDirectory(at url: URL) async throws -> String {
        let fileManager = FileManager.default
        let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        let fileNames = items.prefix(25).map { $0.lastPathComponent }.joined(separator: ", ")
        let dirCount = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }.count
        let fileCount = items.count - dirCount

        let prompt = """
        Directory: \(url.lastPathComponent)
        Contains: \(fileCount) files, \(dirCount) folders.
        Sample items: \(fileNames)
        Provide a concise 1-2 sentence overview of the contents and purpose of this folder.
        """

        return try await generateResponse(prompt: prompt, fallbackDefault: "\(url.lastPathComponent) contains \(fileCount) files and \(dirCount) folders.")
    }

    // MARK: - Tag Suggestions

    /// Suggests 2-4 contextual organizational tags for a given file or folder.
    public func suggestTags(for url: URL) async throws -> [String] {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let prompt = """
        File: \(name) (Extension: \(ext))
        Suggest 2 to 4 short lowercase organization tags (e.g. project, archive, docs, code, design, media).
        Return only comma-separated tags.
        """

        let raw = try await generateResponse(prompt: prompt, fallbackDefault: ext.isEmpty ? "folder, project" : "\(ext), document")
        let tags = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Array(tags.prefix(4))
    }

    // MARK: - File Content Explanation

    /// Explains the purpose and key points of a text or code document.
    public func explainFile(at url: URL) async throws -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.prefix(4000), encoding: .utf8) else {
            return "Binary or non-text file (\(url.pathExtension.uppercased())). Quick Look preview available."
        }

        let prompt = """
        Document: \(url.lastPathComponent)
        Content snippet:
        \(text)

        Explain the purpose and summary of this file in 2 sentences.
        """

        return try await generateResponse(prompt: prompt, fallbackDefault: "Text document (\(url.lastPathComponent)).")
    }

    // MARK: - Engine Routing

    private func generateResponse(prompt: String, fallbackDefault: String) async throws -> String {
        let defaults = UserDefaults.standard
        let isAIEnabled = defaults.bool(forKey: Constants.aiEnabledKey)
        guard isAIEnabled else {
            return fallbackDefault
        }

        let providerRaw = defaults.string(forKey: Constants.aiProviderKey) ?? Provider.appleFoundation.rawValue
        let provider = Provider(rawValue: providerRaw) ?? .appleFoundation

        if provider == .appleFoundation {
            do {
                return try await runOnDeviceFoundationModel(prompt: prompt)
            } catch {
                // If on-device fails and backup is enabled, route to ChatGPT
                if defaults.bool(forKey: Constants.enableAIBackupKey) {
                    return try await runChatGPTBackup(prompt: prompt)
                }
                return fallbackDefault
            }
        } else {
            return try await runChatGPTBackup(prompt: prompt)
        }
    }

    // MARK: - On-Device Foundation Model Execution

    private func runOnDeviceFoundationModel(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw NSError(domain: "AIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Model not available."])
            }
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw NSError(domain: "AIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "FoundationModels framework unavailable on this architecture."])
    }

    // MARK: - ChatGPT Cloud Backup

    private func runChatGPTBackup(prompt: String) async throws -> String {
        let defaults = UserDefaults.standard
        guard let apiKey = defaults.string(forKey: Constants.openAIAPIKeyKey), !apiKey.isEmpty else {
            throw NSError(domain: "AIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "ChatGPT API key missing in Settings."])
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a fast, concise native file manager assistant for macOS Nautica. Answer strictly and directly in 1-2 sentences."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 150
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "ChatGPT API error."])
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw NSError(domain: "AIService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid ChatGPT response structure."])
    }
}
