import XCTest
import CopilotCore

final class SSEDecoderTests: XCTestCase {
    private func events(_ text: String) throws -> [String] {
        var decoder = SSEDecoder()
        return try text.utf8.compactMap { try decoder.consume($0) }
    }
    func testUTF8AndEverySupportedLineEnding() throws {
        for ending in ["\n", "\r\n", "\r"] {
            XCTAssertEqual(try events("\u{FEFF}data: Привет 👋\(ending)data: Go\(ending)\(ending)"), ["Привет 👋\nGo"])
        }
    }
    func testCommentsEmptyDataAndExactlyOneSpace() throws {
        XCTAssertEqual(try events(": keepalive\ndata\ndata:  текст\n\n"), ["\n текст"])
        XCTAssertEqual(try events("data:\n\n"), [""])
        XCTAssertEqual(try events("event: message\nid: 1\n\n"), [])
    }
    func testUnterminatedEventNotDispatched() throws {
        XCTAssertEqual(try events("data: partial\n"), [])
        XCTAssertEqual(try events("data: partial"), [])
    }
    func testOversizedEmptyEventAndInvalidUTF8Rejected() throws {
        XCTAssertThrowsError(try events(String(repeating: "data:\n", count: 16_385)))
        var decoder = SSEDecoder()
        _ = try decoder.consume(0xFF)
        XCTAssertThrowsError(try decoder.consume(10))
    }
}
