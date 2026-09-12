import XCTest
import CopilotCore

final class AnswerDocumentTests: XCTestCase {
    func testHeadingAndCodePreserveIndentationAndSymbols() {
        let blocks = AnswerDocument.blocks("## Решение\nТекст **Go**\n\n```go\nfunc sum() {\n    println(\"<tag>\")\n}\n```\nИтог")
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].kind, .heading(2))
        XCTAssertEqual(blocks[2].kind, .code("go"))
        XCTAssertEqual(blocks[2].text, "func sum() {\n    println(\"<tag>\")\n}")
        XCTAssertEqual(blocks[3].text, "Итог")
    }
    func testUnfinishedStreamAndLongerFences() {
        let blocks = AnswerDocument.blocks("````go\n```\nreturn 1")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .code("go"))
        XCTAssertEqual(blocks[0].text, "```\nreturn 1")
    }
    func testTildeFenceAndCRLF() {
        let blocks = AnswerDocument.blocks("   ~~~sql\r\nSELECT 1;\r\n   ~~~~\r\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .code("sql"))
        XCTAssertEqual(blocks[0].text, "SELECT 1;")
    }
    func testIndentedFenceAndLiteralHashesStayText() {
        let blocks = AnswerDocument.blocks("#include\n    ```go\nСтрока")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .text)
        XCTAssertTrue(blocks[0].text.contains("    ```go"))
    }
}
