import XCTest
@testable import Nautica

final class SplitLayoutTests: XCTestCase {

    func testSplitLayoutPaneCounts() {
        XCTAssertEqual(SplitLayout.single.paneCount, 1)
        XCTAssertEqual(SplitLayout.horizontal2.paneCount, 2)
        XCTAssertEqual(SplitLayout.vertical2.paneCount, 2)
        XCTAssertEqual(SplitLayout.quad4.paneCount, 4)
        XCTAssertEqual(SplitLayout.horizontal4.paneCount, 4)
        XCTAssertEqual(SplitLayout.vertical4.paneCount, 4)
    }

    func testSplitLayoutIcons() {
        XCTAssertEqual(SplitLayout.single.iconName, "rectangle")
        XCTAssertEqual(SplitLayout.horizontal2.iconName, "rectangle.split.2x1")
        XCTAssertEqual(SplitLayout.vertical2.iconName, "rectangle.split.1x2")
        XCTAssertEqual(SplitLayout.quad4.iconName, "rectangle.split.2x2")
        XCTAssertEqual(SplitLayout.horizontal4.iconName, "rectangle.split.3x1")
        XCTAssertEqual(SplitLayout.vertical4.iconName, "rectangle.grid.1x2")
    }

    func testSplitLayoutRawValuesMatchSegmentIndices() {
        XCTAssertEqual(SplitLayout(rawValue: 0), .single)
        XCTAssertEqual(SplitLayout(rawValue: 1), .horizontal2)
        XCTAssertEqual(SplitLayout(rawValue: 2), .vertical2)
        XCTAssertEqual(SplitLayout(rawValue: 3), .quad4)
        XCTAssertEqual(SplitLayout(rawValue: 4), .horizontal4)
        XCTAssertEqual(SplitLayout(rawValue: 5), .vertical4)
    }
}
