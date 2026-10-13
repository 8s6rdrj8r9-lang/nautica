import XCTest
@testable import Nautica

final class FileOperationServiceTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let service = FileOperationService()
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("NauticaTests-" + UUID().uuidString)
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("destination")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fm.removeItem(at: root)
    }

    private func file(_ name: String = "sample.txt", bytes: Int = 1024) throws -> URL {
        let url = source.appendingPathComponent(name)
        try Data(repeating: 42, count: bytes).write(to: url)
        return url
    }

    func testCopyPreservesDanglingDestinationSymlink() async throws {
        let original = try file()
        let link = destination.appendingPathComponent(original.lastPathComponent)
        let missing = root.appendingPathComponent("missing")
        try fm.createSymbolicLink(at: link, withDestinationURL: missing)
        let result = await service.copyItems([original], to: destination, progress: Progress())
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), missing.path)
        XCTAssertEqual(result.succeeded.first?.lastPathComponent, "sample 1.txt")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.succeeded.first)), try Data(contentsOf: original))
    }

    func testDestinationCreatedDuringCopyIsNeverDeleted() async throws {
        let original = try file(bytes: 4 * 1024 * 1024)
        let target = destination.appendingPathComponent(original.lastPathComponent)
        let existing = Data("another writer".utf8)
        let progress = ObservedProgress()
        var creationError: Error?
        progress.onAdvance = { progress in
            guard progress.completedUnitCount > 0 else { return }
            progress.onAdvance = nil
            do { try existing.write(to: target) } catch { creationError = error }
        }
        let result = await service.copyItems([original], to: destination, progress: progress)
        XCTAssertNil(creationError)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(try Data(contentsOf: target), existing)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: destination.path), ["sample.txt"])
    }

    func testUndoRestoresOriginalNameAfterCollision() async throws {
        let original = try file()
        let existing = destination.appendingPathComponent(original.lastPathComponent)
        try Data("existing".utf8).write(to: existing)
        let moved = await service.moveItems([original], to: destination, progress: Progress())
        XCTAssertEqual(moved.succeeded.first?.lastPathComponent, "sample 1.txt")
        let restored = await service.restoreItems(moved.transfers)
        XCTAssertTrue(restored.failed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
    }

    func testPartialMoveKeepsCorrectSuccessfulSourceForUndo() async throws {
        let missing = source.appendingPathComponent("missing.txt")
        let original = try file()
        let moved = await service.moveItems([missing, original], to: destination, progress: Progress())
        XCTAssertEqual(moved.failed.count, 1)
        XCTAssertEqual(moved.transfers.map(\.original), [original])
        let restored = await service.restoreItems(moved.transfers)
        XCTAssertTrue(restored.failed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: original.path))
        XCTAssertFalse(fm.fileExists(atPath: missing.path))
    }

    func testUndoCollisionPreservesBothFiles() async throws {
        let original = try file()
        let moved = await service.moveItems([original], to: destination, progress: Progress())
        let movedURL = try XCTUnwrap(moved.succeeded.first)
        try Data("replacement".utf8).write(to: original)
        let restored = await service.restoreItems(moved.transfers)
        XCTAssertEqual(restored.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertTrue(fm.fileExists(atPath: movedURL.path))
    }

    func testCancelDuringFileCopyRemovesOnlyStagingFiles() async throws {
        let original = try file(bytes: 8 * 1024 * 1024)
        let progress = ObservedProgress()
        progress.onAdvance = { if $0.completedUnitCount > 0 { $0.cancel() } }
        let result = await service.copyItems([original], to: destination, progress: progress)
        XCTAssertTrue(progress.isCancelled)
        XCTAssertLessThan(progress.completedUnitCount, progress.totalUnitCount)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.failed.first?.1 is CancellationError)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: destination.path), [])
        XCTAssertEqual(try Data(contentsOf: original).count, 8 * 1024 * 1024)
    }

    func testCancelDuringDirectoryCopyRemovesPartialTree() async throws {
        _ = try file(bytes: 8 * 1024 * 1024)
        let progress = ObservedProgress()
        progress.onAdvance = { if $0.completedUnitCount > 0 { $0.cancel() } }
        let result = await service.copyItems([source], to: destination, progress: progress)
        XCTAssertTrue(result.failed.first?.1 is CancellationError)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: destination.path), [])
    }

    func testRecursiveCopyPreservesSymlinksAndPermissions() async throws {
        let original = try file()
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: original.path)
        try fm.createSymbolicLink(atPath: source.appendingPathComponent("link").path,
                                  withDestinationPath: "sample.txt")
        let result = await service.copyItems([source], to: destination, progress: Progress())
        XCTAssertTrue(result.failed.isEmpty)
        let copied = try XCTUnwrap(result.succeeded.first)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: copied.appendingPathComponent("link").path), "sample.txt")
        let attributes = try fm.attributesOfItem(atPath: copied.appendingPathComponent("sample.txt").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }

    func testCopyIntoOwnDescendantFailsWithoutCreatingPartialFiles() async throws {
        let child = source.appendingPathComponent("child")
        try fm.createDirectory(at: child, withIntermediateDirectories: false)
        let result = await service.copyItems([source], to: child, progress: Progress())
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: child.path), [])
    }

    func testEnumerationFailureThrowsInsteadOfReturningEmptyListing() async throws {
        let original = try file()
        do {
            _ = try await FileSystemService.shared.contentsOfDirectory(at: original, includingHidden: true)
            XCTFail("A regular file is not a readable directory")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
        let empty = try await FileSystemService.shared.contentsOfDirectory(at: destination, includingHidden: true)
        XCTAssertTrue(empty.isEmpty)
    }
}

private final class ObservedProgress: Progress, @unchecked Sendable {
    var onAdvance: ((ObservedProgress) -> Void)?
    override var completedUnitCount: Int64 {
        didSet { onAdvance?(self) }
    }
}
