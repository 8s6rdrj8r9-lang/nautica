import XCTest
@testable import Nautica

@MainActor
final class StorageModelTests: XCTestCase {
    func testStorageModelEnumeratesVolumes() {
        let model = StorageModel()
        XCTAssertFalse(model.volumes.isEmpty, "StorageModel should find at least the root volume")
        XCTAssertNotNil(model.rootVolume, "StorageModel should have a rootVolume")
        XCTAssertEqual(model.rootVolume?.url.path, "/", "Root volume should have path /")
    }

    func testStorageModelFindsVolumeForURL() {
        let model = StorageModel()
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let volume = model.volume(for: homeURL)
        XCTAssertNotNil(volume, "StorageModel should find a volume for user home directory")
    }

    func testStorageVolumeCalculatesUsedAndRatio() {
        let vol = StorageVolume(
            url: URL(fileURLWithPath: "/"),
            name: "Test HD",
            totalCapacity: 1_000_000_000,
            availableCapacity: 400_000_000,
            fileSystemType: "APFS"
        )
        XCTAssertEqual(vol.usedCapacity, 600_000_000)
        XCTAssertEqual(vol.usageRatio, 0.6, accuracy: 0.001)
        XCTAssertFalse(vol.formattedTotal.isEmpty)
        XCTAssertFalse(vol.formattedAvailable.isEmpty)
        XCTAssertFalse(vol.formattedUsed.isEmpty)
    }
}
