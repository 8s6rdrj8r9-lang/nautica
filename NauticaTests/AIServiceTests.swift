import XCTest
@testable import Nautica

final class AIServiceTests: XCTestCase {
    func testCloudRequiresCurrentConsentAndExplicitCloudChoice() throws {
        let suite = "NauticaAIConsentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults))
        defaults.set(true, forKey: Constants.aiEnabledKey)
        defaults.set(true, forKey: Constants.enableAIBackupKey)
        defaults.set(AIService.Provider.openAI.rawValue, forKey: Constants.aiProviderKey)
        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults), "Legacy cloud settings cannot authorize egress")
        defaults.set(AICloudPolicy.version, forKey: AICloudPolicy.consentKey)
        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults), "Local-only has a safe default")
        defaults.set(false, forKey: AICloudPolicy.localOnlyKey)
        XCTAssertTrue(AICloudPolicy.allowsCloud(defaults: defaults))
        defaults.set(true, forKey: AICloudPolicy.localOnlyKey)
        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults), "Local-only overrides consent")
        defaults.set(false, forKey: AICloudPolicy.localOnlyKey)
        defaults.set("older-disclosure", forKey: AICloudPolicy.consentKey)
        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults))
        defaults.set(AICloudPolicy.version, forKey: AICloudPolicy.consentKey)
        defaults.set(false, forKey: Constants.aiEnabledKey)
        XCTAssertFalse(AICloudPolicy.allowsCloud(defaults: defaults), "Disabled Intelligence cannot send cloud requests")
    }
}
