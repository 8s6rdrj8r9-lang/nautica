//
//  AIServiceTests.swift
//  NauticaTests
//
//  EnsDev macOS 27 Foundation Models & Backup Fallback Contract Tests
//

import XCTest
@testable import Nautica

final class AIServiceTests: XCTestCase {

    override func setUp() async throws {
        // Reset test keys to baseline
        UserDefaults.standard.removeObject(forKey: Constants.aiEnabledKey)
        UserDefaults.standard.removeObject(forKey: Constants.aiProviderKey)
        UserDefaults.standard.removeObject(forKey: Constants.aiBackupProviderKey)
        UserDefaults.standard.removeObject(forKey: Constants.enableAIBackupKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Constants.aiEnabledKey)
        UserDefaults.standard.removeObject(forKey: Constants.aiProviderKey)
        UserDefaults.standard.removeObject(forKey: Constants.aiBackupProviderKey)
        UserDefaults.standard.removeObject(forKey: Constants.enableAIBackupKey)
    }

    func testAIServiceDefaultConfiguration() async {
        let ai = AIService.shared
        // By default, AI should default to Apple Foundation Models
        let provider = await ai.activeProvider
        XCTAssertEqual(provider, .appleFoundation, "Default AI provider must be on-device Apple Foundation Models")

        let backup = await ai.backupProvider
        XCTAssertEqual(backup, .openai, "Default backup AI provider must be OpenAI")

        let backupEnabled = await ai.isBackupEnabled
        XCTAssertFalse(backupEnabled, "Backup fallback must be disabled by default (opt-in cloud privacy)")
    }

    func testAIServiceSummarizeFileRequiresOptInWhenDisabled() async {
        let ai = AIService.shared
        UserDefaults.standard.set(false, forKey: Constants.aiEnabledKey)

        let tempURL = URL(fileURLWithPath: "/tmp/nautica-test-ai-disabled.txt")
        try? "Sample content for testing".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await ai.summarizeFile(at: tempURL)
            XCTFail("Should throw disabled error when AI is disabled")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disabled") || (error as? AIServiceError) == .disabled)
        }
    }

    func testAIServiceSummarizeFileThrowsForNonExistentFile() async {
        let ai = AIService.shared
        UserDefaults.standard.set(true, forKey: Constants.aiEnabledKey)

        let missingURL = URL(fileURLWithPath: "/tmp/nautica-nonexistent-\(UUID().uuidString).txt")

        do {
            _ = try await ai.summarizeFile(at: missingURL)
            XCTFail("Should throw fileNotFound error")
        } catch {
            XCTAssertEqual(error as? AIServiceError, .fileNotFound)
        }
    }
}
