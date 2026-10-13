import XCTest
@testable import Nautica

final class BatchRenameTests: XCTestCase {

    private func makeFileItem(name: String, in dir: URL) -> FileItem {
        let url = dir.appendingPathComponent(name)
        return FileItem(
            url: url,
            name: name,
            isDirectory: false,
            size: 100,
            modificationDate: Date(),
            creationDate: Date(),
            isHidden: false,
            kind: "Document"
        )
    }

    func testSequenceRenameWithHashes() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "img1.jpg", in: tempDir),
            makeFileItem(name: "img2.jpg", in: tempDir),
            makeFileItem(name: "img3.jpg", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .sequence
        model.sequencePattern = "vacation_###.jpg"
        model.startIndex = 1

        let previews = model.previewItems
        XCTAssertEqual(previews.count, 3)
        XCTAssertEqual(previews[0].newName, "vacation_001.jpg")
        XCTAssertEqual(previews[1].newName, "vacation_002.jpg")
        XCTAssertEqual(previews[2].newName, "vacation_003.jpg")
        XCTAssertFalse(model.hasConflicts)
        XCTAssertTrue(model.canApply)
    }

    func testSequenceRenameWithoutHashesAppendsDigits() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "docA.pdf", in: tempDir),
            makeFileItem(name: "docB.pdf", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .sequence
        model.sequencePattern = "archive_"
        model.startIndex = 10
        model.paddingDigits = 4
        model.keepExtension = true

        let previews = model.previewItems
        XCTAssertEqual(previews[0].newName, "archive_0010.pdf")
        XCTAssertEqual(previews[1].newName, "archive_0011.pdf")
        XCTAssertFalse(model.hasConflicts)
    }

    func testFindAndReplace() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "draft_v1_notes.txt", in: tempDir),
            makeFileItem(name: "draft_v2_notes.txt", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .findReplace
        model.findText = "draft"
        model.replaceText = "final"

        let previews = model.previewItems
        XCTAssertEqual(previews[0].newName, "final_v1_notes.txt")
        XCTAssertEqual(previews[1].newName, "final_v2_notes.txt")
        XCTAssertFalse(model.hasConflicts)
    }

    func testAddPrefixAndSuffix() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "summary.pdf", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .addText
        model.prefixText = "Q4_"
        model.suffixText = "_Reviewed"

        let previews = model.previewItems
        XCTAssertEqual(previews[0].newName, "Q4_summary_Reviewed.pdf")
        XCTAssertFalse(model.hasConflicts)
    }

    func testConflictDetectionDuplicateNewNames() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "first.txt", in: tempDir),
            makeFileItem(name: "second.txt", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .sequence
        // Pattern without sequence placeholder produces duplicate names
        model.sequencePattern = "constant.txt"
        model.paddingDigits = 0

        // If pattern has no '#' and padding is 0, wait, our computeSequenceName:
        // let numberString = String(format: "%0*d", max(1, paddingDigits), number)
        // Let's test find & replace that produces duplicate:
        model.mode = .findReplace
        model.findText = "first"
        model.replaceText = "second" // "first.txt" -> "second.txt", duplicate with existing

        let previews = model.previewItems
        XCTAssertTrue(model.hasConflicts)
        XCTAssertFalse(model.canApply)
        XCTAssertTrue(previews.contains { $0.hasConflict })
    }

    func testConflictDetectionIllegalCharacters() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let items = [
            makeFileItem(name: "notes.txt", in: tempDir),
        ]

        let model = BatchRenameModel(items: items)
        model.mode = .findReplace
        model.findText = "notes"
        model.replaceText = "my/notes:invalid"

        let previews = model.previewItems
        XCTAssertTrue(model.hasConflicts)
        XCTAssertEqual(previews[0].conflictReason, "Cannot contain '/' or ':'")
    }

    func testBatchRenameExecutionAndUndo() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("batch_rename_test_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("orig1.txt")
        let file2 = tempDir.appendingPathComponent("orig2.txt")
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)

        let renames: [(url: URL, newName: String)] = [
            (file1, "renamed1.txt"),
            (file2, "renamed2.txt"),
        ]

        let result = await FileOperationService.shared.renameItems(renames)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(result.transfers.count, 2)

        let newFile1 = tempDir.appendingPathComponent("renamed1.txt")
        let newFile2 = tempDir.appendingPathComponent("renamed2.txt")
        XCTAssertTrue(fm.fileExists(atPath: newFile1.path))
        XCTAssertTrue(fm.fileExists(atPath: newFile2.path))
        XCTAssertFalse(fm.fileExists(atPath: file1.path))
        XCTAssertFalse(fm.fileExists(atPath: file2.path))

        // Test Undo (restoreItems)
        let undoResult = await FileOperationService.shared.restoreItems(result.transfers)
        XCTAssertTrue(undoResult.failed.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: file1.path))
        XCTAssertTrue(fm.fileExists(atPath: file2.path))
        XCTAssertFalse(fm.fileExists(atPath: newFile1.path))
        XCTAssertFalse(fm.fileExists(atPath: newFile2.path))
    }
}
