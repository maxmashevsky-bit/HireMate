import XCTest
import CopilotCore

final class AnswerDocumentTests: XCTestCase {
    func testGoHighlightingPreservesCodeAndSeparatesCommentsStringsAndKeywords() {
        let code = "package main\r\n// func 123\nvar привет = `return // текст`\nfunc f() { println(\"go \\\"var\\\"\", 1e-3, 10-2) }"
        let tokens = AnswerDocument.codeTokens(code, language: " Go ")
        XCTAssertEqual(tokens.map(\.text).joined(), code)
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.map(\.text), ["package", "var", "func"])
        XCTAssertEqual(tokens.filter { $0.kind == .comment }.map(\.text), ["// func 123"])
        XCTAssertEqual(tokens.filter { $0.kind == .number }.map(\.text), ["1e-3", "10", "2"])
        XCTAssertEqual(tokens.filter { $0.kind == .string }.map(\.text), ["`return // текст`", "\"go \\\"var\\\"\""])
    }

    func testGoHighlightingHandlesUnfinishedStringAndCommentDuringStreaming() {
        for code in ["var x = \"незавершённая\\", "/* func\nreturn", "var y = `строка\n// go"] {
            let tokens = AnswerDocument.codeTokens(code, language: "golang")
            XCTAssertEqual(tokens.map(\.text).joined(), code)
            XCTAssertFalse(tokens.isEmpty)
            XCTAssertTrue(tokens.last?.kind == .string || tokens.last?.kind == .comment)
        }
    }

    func testUnsupportedLanguagesAndLargeCodeRemainVisibleWithoutHighlighting() {
        for (code, language) in [("SELECT 'func';", "sql"), (String(repeating: "func ", count: 26000), "go")] {
            let tokens = AnswerDocument.codeTokens(code, language: language)
            XCTAssertEqual(tokens.map(\.text).joined(), code)
            XCTAssertEqual(tokens.count, 1)
            XCTAssertEqual(tokens.first?.kind, .plain)
        }
        XCTAssertTrue(AnswerDocument.codeTokens("", language: "go").isEmpty)
    }

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

    func testListsKeepActualNumbersAndDoNotInterpretOrdinaryPunctuation() {
        let blocks = AnswerDocument.blocks("Вступление\n- **Go**\n+ Swift\n3. первый\n9) второй\n1.2 версия\n1234567890. слишком длинно\n    - не список")
        XCTAssertEqual(blocks.count, 4)
        guard case .list(let bullets) = blocks[1].kind, case .list(let numbered) = blocks[2].kind else {
            return XCTFail("Ожидались отдельные маркированный и нумерованный списки")
        }
        XCTAssertEqual(bullets.map(\.marker), ["•", "•"])
        XCTAssertEqual(bullets.map(\.text), ["**Go**", "Swift"])
        XCTAssertEqual(numbered.map(\.marker), ["3.", "9)"])
        XCTAssertEqual(numbered.map(\.text), ["первый", "второй"])
        XCTAssertEqual(blocks[3].text, "1.2 версия\n1234567890. слишком длинно\n    - не список")
    }

    func testQuotesAndRulesStayOutsideCodeAndPreserveQuotedLineBreaks() {
        let blocks = AnswerDocument.blocks("> **важно**\n>\n> 👩🏽‍💻 ответ\n\n- - -\n***\n```text\n> код\n---\n```\n    ---")
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0].kind, .quote)
        XCTAssertEqual(blocks[0].text, "**важно**\n\n👩🏽‍💻 ответ")
        XCTAssertEqual(blocks[1].kind, .horizontalRule)
        XCTAssertEqual(blocks[2].kind, .horizontalRule)
        XCTAssertEqual(blocks[3].kind, .code("text"))
        XCTAssertEqual(blocks[3].text, "> код\n---")
        XCTAssertEqual(blocks[4].kind, .text)
        XCTAssertEqual(blocks[4].text, "    ---")
    }

    func testTableAlignmentEscapedPipesAndInlineCodeWithoutLosingContent() {
        let source = "| Лево | Центр | Право |\r\n| :--- | :---: | ---: |\r\n| a\\|b | `x|y` | 👩🏽‍💻 |\r\n| \\*text\\* | **Go** | 42 |\r\nИтог"
        let blocks = AnswerDocument.blocks(source)
        XCTAssertEqual(blocks.count, 2)
        guard case .table(let table) = blocks[0].kind else { return XCTFail("Таблица не распознана") }
        XCTAssertEqual(table.headers, ["Лево", "Центр", "Право"])
        XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
        XCTAssertEqual(table.rows, [["a|b", "`x|y`", "👩🏽‍💻"], ["\\*text\\*", "**Go**", "42"]])
        XCTAssertEqual(blocks[1].text, "Итог")
    }

    func testMalformedAndUnfinishedTablesRemainVisibleAndNeverDropExtraCells() {
        for source in ["a | b\n-- | ---\n1 | 2", "a | b\n--- | --- | ---\n1 | 2",
                       "    | a | b |\n    | --- | --- |", "`a|b`\n| --- |"] {
            let blocks = AnswerDocument.blocks(source)
            XCTAssertEqual(blocks.count, 1)
            XCTAssertEqual(blocks[0].kind, .text)
            XCTAssertEqual(blocks[0].text, source)
        }
        let blocks = AnswerDocument.blocks("a | b\n--- | ---\n1 | 2 | не потерять\nКонец")
        guard case .table(let table) = blocks[0].kind else { return XCTFail("Таблица заголовка не распознана") }
        XCTAssertTrue(table.rows.isEmpty)
        XCTAssertEqual(blocks[1].text, "1 | 2 | не потерять\nКонец")
        XCTAssertEqual(AnswerDocument.blocks("a | b\n--- |").first?.kind, .text)
    }

    func testWideTablesFallbackToVisibleTextAndBackslashParityPreservesCells() {
        let header = Array(repeating: "H", count: 33).joined(separator: " | ")
        let separator = Array(repeating: "---", count: 33).joined(separator: " | ")
        XCTAssertEqual(AnswerDocument.blocks(header + "\n" + separator).first?.kind, .text)
        let blocks = AnswerDocument.blocks("| H | V |\n| --- | --- |\n| a\\\\ | b |\n| a\\\\\\|b | c |")
        guard case .table(let table) = blocks.first?.kind else { return XCTFail("Таблица не распознана") }
        XCTAssertEqual(table.rows, [["a\\\\", "b"], ["a\\\\|b", "c"]])
    }
}
