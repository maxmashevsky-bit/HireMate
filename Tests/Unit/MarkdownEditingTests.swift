import XCTest
import CopilotCore

final class MarkdownEditingTests: XCTestCase {
    func testFormatsUnicodeSelectionAndTogglesWithoutChangingOtherText() throws {
        let text = "До 👩🏽‍💻 и Go после"
        let selected = (text as NSString).range(of: "👩🏽‍💻 и Go")
        let bold = try XCTUnwrap(MarkdownEditing.apply(.bold, to: text, selection: selected))
        XCTAssertEqual(bold.text, "До **👩🏽‍💻 и Go** после")
        XCTAssertEqual((bold.text as NSString).substring(with: bold.selection), "👩🏽‍💻 и Go")
        let plain = try XCTUnwrap(MarkdownEditing.apply(.bold, to: bold.text, selection: bold.selection))
        XCTAssertEqual(plain.text, text)
        XCTAssertEqual(plain.selection, selected)
        let fullMarker = (bold.text as NSString).range(of: "**👩🏽‍💻 и Go**")
        XCTAssertEqual(MarkdownEditing.apply(.bold, to: bold.text, selection: fullMarker)?.text, text)
    }

    func testCaretInsertionSelectsPlaceholderAndLeavesExistingText() throws {
        let edit = try XCTUnwrap(MarkdownEditing.apply(.italic, to: "до после", selection: NSRange(location: 3, length: 0)))
        XCTAssertEqual(edit.text, "до *текст*после")
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), "текст")
        XCTAssertEqual(MarkdownEditing.apply(.strikethrough, to: "")?.text, "~~текст~~")
    }

    func testListFormattingExpandsSelectedLinesAndPreservesTrailingNewline() throws {
        let text = "снаружи\nпервая\nвторая\nпосле"
        let selected = (text as NSString).range(of: "вая\nвто")
        let list = try XCTUnwrap(MarkdownEditing.apply(.numberedList, to: text, selection: selected))
        XCTAssertEqual(list.text, "снаружи\n1. первая\n2. вторая\nпосле")
        XCTAssertEqual((list.text as NSString).substring(with: list.selection), "1. первая\n2. вторая\n")
        let quote = try XCTUnwrap(MarkdownEditing.apply(.quote, to: "строка\n", selection: NSRange(location: 2, length: 0)))
        XCTAssertEqual(quote.text, "> строка\n")
        XCTAssertEqual(MarkdownEditing.apply(.bulletList, to: "")?.text, "- текст")
    }

    func testCodeBlockUsesLongerFenceAndRemainsOneBlockInPreview() throws {
        let original = "```go\nfunc main() {}\n```"
        let edit = try XCTUnwrap(MarkdownEditing.apply(.codeBlock, to: original,
                                                      selection: NSRange(location: 0, length: original.utf16.count)))
        XCTAssertTrue(edit.text.hasPrefix("````\n"))
        XCTAssertEqual(AnswerDocument.blocks(edit.text).count, 1)
        XCTAssertEqual(AnswerDocument.blocks(edit.text).first?.text, original)
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), original)
    }

    func testLinkSelectsAddressAndTableEscapesPipe() throws {
        let link = try XCTUnwrap(MarkdownEditing.apply(.link, to: "Go", selection: NSRange(location: 0, length: 2)))
        XCTAssertEqual(link.text, "[Go](https://example.com)")
        XCTAssertEqual((link.text as NSString).substring(with: link.selection), "https://example.com")
        let table = try XCTUnwrap(MarkdownEditing.apply(.table, to: "a|b", selection: NSRange(location: 0, length: 3)))
        XCTAssertTrue(table.text.contains("| a\\|b | текст |"))
        XCTAssertEqual((table.text as NSString).substring(with: table.selection), "Заголовок")
    }

    func testInvalidUnicodeRangesAndSizeLimitsNeverChangeText() {
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 1),
                      NSRange(location: 0, length: -1), NSRange(location: 1, length: 1),
                      NSRange(location: 0, length: Int.max)] {
            XCTAssertNil(MarkdownEditing.apply(.bold, to: "😀", selection: range))
        }
        XCTAssertNil(MarkdownEditing.apply(.italic, to: "e\u{301}", selection: NSRange(location: 1, length: 1)))
        XCTAssertNil(MarkdownEditing.apply(.italic, to: "😀", selection: NSRange(location: 1, length: 0)))
        let atLimit = String(repeating: "a", count: 1_048_576)
        XCTAssertNil(MarkdownEditing.apply(.bold, to: atLimit))
        XCTAssertNil(MarkdownEditing.apply(.quote, to: atLimit + "a"))
    }

    func testInlineCodeUsesSafeFenceAndRepeatPreservesSelectedContent() throws {
        for body in ["Go 👩🏽‍💻", "`a|b`", "код `` здесь", " пробелы "] {
            let edit = try XCTUnwrap(MarkdownEditing.apply(.inlineCode, to: body, selection: NSRange(location: 0, length: body.utf16.count)))
            XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), body)
            XCTAssertEqual(MarkdownEditing.apply(.inlineCode, to: edit.text, selection: edit.selection)?.text, body)
            XCTAssertFalse(edit.text.hasPrefix("```\n"))
        }
        XCTAssertEqual(MarkdownEditing.apply(.inlineCode, to: "")?.text, "`код`")
        XCTAssertNil(MarkdownEditing.apply(.inlineCode, to: "две\nстроки", selection: NSRange(location: 0, length: 10)))
    }

    func testHeadingChangesExistingLevelAndRepeatRestoresPlainLines() throws {
        let source = "снаружи\n## первая\nвторая\nпосле"
        let range = (source as NSString).range(of: "первая\nвто")
        let heading = try XCTUnwrap(MarkdownEditing.apply(.heading3, to: source, selection: range))
        XCTAssertEqual(heading.text, "снаружи\n### первая\n### вторая\nпосле")
        let plain = try XCTUnwrap(MarkdownEditing.apply(.heading3, to: heading.text, selection: heading.selection))
        XCTAssertEqual(plain.text, "снаружи\nпервая\nвторая\nпосле")
        XCTAssertEqual(MarkdownEditing.apply(.heading1, to: "")?.text, "# Заголовок")
        let literal = try XCTUnwrap(MarkdownEditing.apply(.heading2, to: "#include", selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(literal.text, "## #include")
        XCTAssertEqual(AnswerDocument.blocks(literal.text).first?.kind, .heading(2))
    }

    func testDividerKeepsSelectedTextAndCreatesSeparateVisibleBlocks() throws {
        let source = "до текст после"
        let edit = try XCTUnwrap(MarkdownEditing.apply(.horizontalRule, to: source,
                                                      selection: (source as NSString).range(of: "текст")))
        XCTAssertEqual(edit.text, "до текст\n\n---\n\n после")
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selection), "---")
        let blocks = AnswerDocument.blocks(edit.text)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].kind, .horizontalRule)
        XCTAssertEqual(MarkdownEditing.apply(.horizontalRule, to: "")?.text, "---")
    }
}
