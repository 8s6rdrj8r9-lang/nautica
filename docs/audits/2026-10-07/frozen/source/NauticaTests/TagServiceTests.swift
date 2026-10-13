import XCTest
@testable import Nautica

final class TagServiceTests: XCTestCase {
    override func setUp() async throws {
        try await TagService.shared.setupDatabase()
    }

    /// Distinct tag name per run so the shared on-disk database stays usable
    /// even if a previous run was interrupted.
    private func uniqueName(_ base: String) -> String {
        "\(base)-\(UUID().uuidString.prefix(8))"
    }

    func testCreateTagPersists() async throws {
        let name = uniqueName("Red")
        let tag = try await TagService.shared.createTag(name: name, colorHex: "#FF0000")

        let all = try await TagService.shared.allTags()
        XCTAssertTrue(all.contains(where: { $0.id == tag.id }), "Created tag must persist to SQLite")

        try await TagService.shared.deleteTag(id: tag.id)
    }

    func testApplyAndQueryTagsForFile() async throws {
        let tag = try await TagService.shared.createTag(name: uniqueName("Red"), colorHex: "#FF0000")
        let file = URL(fileURLWithPath: "/tmp/nautica-tag-test.txt")

        try await TagService.shared.applyTag(tag.id, to: file)
        // Applying twice must be a no-op (UNIQUE constraint).
        try await TagService.shared.applyTag(tag.id, to: file)

        let tags = try await TagService.shared.tagsForFile(file)
        XCTAssertEqual(tags.map(\.id), [tag.id])
        let files = try await TagService.shared.filesWithTag(tag.id)
        XCTAssertEqual(files, [file])

        try await TagService.shared.removeTag(tag.id, from: file)
        let remaining = try await TagService.shared.tagsForFile(file)
        XCTAssertTrue(remaining.isEmpty)

        try await TagService.shared.deleteTag(id: tag.id)
    }

    func testDeleteTagCascadesToFileTags() async throws {
        let tag = try await TagService.shared.createTag(name: uniqueName("Red"), colorHex: "#FF0000")
        let file = URL(fileURLWithPath: "/tmp/nautica-cascade-test.txt")
        try await TagService.shared.applyTag(tag.id, to: file)

        try await TagService.shared.deleteTag(id: tag.id)

        let all = try await TagService.shared.allTags()
        XCTAssertFalse(all.contains(where: { $0.id == tag.id }))
        let files = try await TagService.shared.filesWithTag(tag.id)
        XCTAssertTrue(files.isEmpty, "ON DELETE CASCADE must remove file_tag rows")
    }
}
