import XCTest
@testable import Nautica

final class GitServiceTests: XCTestCase {
    func testUnquotePorcelainPathSimpleAndEscaped() {
        let service = GitService.shared
        XCTAssertEqual(service.unquotePorcelainPath("clean_file.txt"), "clean_file.txt")
        XCTAssertEqual(service.unquotePorcelainPath("\"file with spaces.txt\""), "file with spaces.txt")
        XCTAssertEqual(service.unquotePorcelainPath("\"quote\\\"inside.txt\""), "quote\"inside.txt")
        XCTAssertEqual(service.unquotePorcelainPath("\"tab\\tseparated.txt\""), "tab\tseparated.txt")
        XCTAssertEqual(service.unquotePorcelainPath("\"newline\\nseparated.txt\""), "newline\nseparated.txt")
    }

    func testUnquotePorcelainPathOctalEscapes() {
        let service = GitService.shared
        // Octal 303 251 is UTF-8 for é (0xC3 0xA9)
        let octalStr = "\"caf\\303\\251.txt\""
        let unquoted = service.unquotePorcelainPath(octalStr)
        XCTAssertEqual(unquoted, "café.txt")
    }
}
