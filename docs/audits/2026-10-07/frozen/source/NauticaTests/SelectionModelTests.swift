import XCTest
@testable import Nautica

final class SelectionModelTests: XCTestCase {
    private func makeItems(_ count: Int) -> [FileItem] {
        (0..<count).map { index in
            FileItem(
                url: URL(fileURLWithPath: "/tmp/file\(index)"),
                name: "file\(index)",
                isDirectory: false,
                size: nil,
                modificationDate: nil,
                creationDate: nil,
                isHidden: false,
                kind: ""
            )
        }
    }

    func testPlainClickSelectsOnlyClickedItem() {
        let items = makeItems(5)
        let model = SelectionModel()

        model.handleClick(items[1].id, modifierFlags: [], in: items)
        XCTAssertEqual(model.selectedIDs, [items[1].id])

        model.handleClick(items[3].id, modifierFlags: [], in: items)
        XCTAssertEqual(model.selectedIDs, [items[3].id], "Plain click must deselect previous items")
        XCTAssertEqual(model.lastClickedID, items[3].id)
    }

    func testCommandClickTogglesItem() {
        let items = makeItems(5)
        let model = SelectionModel()

        model.handleClick(items[0].id, modifierFlags: [], in: items)
        model.handleClick(items[2].id, modifierFlags: .command, in: items)
        XCTAssertEqual(model.selectedIDs, [items[0].id, items[2].id], "Cmd-click must add to selection")

        model.handleClick(items[0].id, modifierFlags: .command, in: items)
        XCTAssertEqual(model.selectedIDs, [items[2].id], "Cmd-click on selected item must remove it")
    }

    func testShiftClickSelectsContiguousRange() {
        let items = makeItems(6)
        let model = SelectionModel()

        model.handleClick(items[1].id, modifierFlags: [], in: items)
        model.handleClick(items[4].id, modifierFlags: .shift, in: items)

        XCTAssertEqual(
            model.selectedIDs,
            Set(items[1...4].map(\.id)),
            "Shift-click must select the range from the anchor to the clicked item"
        )
    }

    func testShiftClickWithoutAnchorSelectsFromFirstItem() {
        let items = makeItems(5)
        let model = SelectionModel()

        model.handleClick(items[2].id, modifierFlags: .shift, in: items)

        XCTAssertEqual(model.selectedIDs, Set(items[0...2].map(\.id)))
    }

    func testSelectAllAndDeselectAll() {
        let items = makeItems(4)
        let model = SelectionModel()

        model.selectAll(in: items)
        XCTAssertEqual(model.selectedIDs.count, 4)

        model.deselectAll()
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.anchorID)
        XCTAssertNil(model.lastClickedID)
    }

    func testInvertSelection() {
        let items = makeItems(4)
        let model = SelectionModel()

        model.handleClick(items[0].id, modifierFlags: [], in: items)
        model.handleClick(items[1].id, modifierFlags: .command, in: items)
        model.invertSelection(in: items)

        XCTAssertEqual(model.selectedIDs, [items[2].id, items[3].id])
    }

    func testMoveSelectionByArrowKey() {
        let items = makeItems(5)
        let model = SelectionModel()

        // No selection: down selects the first item.
        model.moveSelection(by: 1, in: items, extending: false)
        XCTAssertEqual(model.selectedIDs, [items[0].id])

        model.moveSelection(by: 1, in: items, extending: false)
        XCTAssertEqual(model.selectedIDs, [items[1].id])

        // Clamps at the end.
        model.moveSelection(by: 99, in: items, extending: false)
        XCTAssertEqual(model.selectedIDs, [items[4].id])
    }

    func testShiftArrowExtendsSelection() {
        let items = makeItems(5)
        let model = SelectionModel()

        model.handleClick(items[1].id, modifierFlags: [], in: items)
        model.moveSelection(by: 2, in: items, extending: true)

        XCTAssertEqual(model.selectedIDs, Set(items[1...3].map(\.id)))
    }

    func testTypeAheadMatchesCaseInsensitivePrefix() {
        var items = makeItems(3)
        items[0] = FileItem(
            url: URL(fileURLWithPath: "/Applications/Calculator.app"),
            name: "Calculator.app",
            isDirectory: true,
            size: nil,
            modificationDate: nil,
            creationDate: nil,
            isHidden: false,
            kind: "Application"
        )

        var buffer = TypeAheadBuffer()
        buffer.append("c")
        buffer.append("a")
        buffer.append("l")

        XCTAssertEqual(buffer.match(in: items)?.name, "Calculator.app")
    }

    func testTypeAheadBufferExpiresAfterTimeout() {
        var buffer = TypeAheadBuffer()
        let start = Date()
        buffer.append("a", at: start)
        buffer.append("b", at: start.addingTimeInterval(TypeAheadBuffer.timeout + 0.1))

        XCTAssertEqual(buffer.buffer, "b", "Keystrokes after the timeout must restart the buffer")
    }
}
