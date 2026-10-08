import XCTest
import CopilotCore

final class NoteChunkerTests: XCTestCase {
    func testTenThousandShortParagraphsHaveBoundedChunkCountWithoutLosingText() {
        let text = (0..<10_000).map { "Строка \($0)" }.joined(separator: "\n\n")
        let note = Note(profileID: .technical, title: "Много абзацев", markdown: text)
        let fragments = NoteChunker.chunks(note)
        XCTAssertLessThan(fragments.count, 250)
        XCTAssertTrue(fragments.allSatisfy { !$0.text.isEmpty && $0.text.count <= 800 })
        XCTAssertEqual(fragments.map(\.text).joined(separator: "\n\n"), text)
        XCTAssertEqual(fragments.map(\.index), Array(0..<fragments.count))
        XCTAssertTrue(fragments.allSatisfy { $0.sourceHash == note.contentHash && $0.profileID == .technical })
    }

    func testLongUnicodeBlockKeepsBoundedOverlapAndEveryCharacter() {
        let text = String(repeating: "👩🏽‍💻", count: 5_000)
        let note = Note(profileID: .hr, markdown: text)
        let fragments = NoteChunker.chunks(note)
        XCTAssertTrue(fragments.allSatisfy { $0.text.count <= 800 })
        let reconstructed = (fragments.first?.text ?? "") + fragments.dropFirst().map { String($0.text.dropFirst(100)) }.joined()
        XCTAssertEqual(reconstructed, text)
        XCTAssertEqual(fragments.count, 7)
    }

    func testEmptyTitleFallbackAndInvalidTuningRemainBounded() {
        let note = Note(profileID: .liveCoding, title: "Название", markdown: "\n\n")
        XCTAssertEqual(NoteChunker.chunks(note).map(\.text), ["Название"])
        let text = "# Заголовок\r\n\r\nПервый\rВторой"
        let normalized = NoteChunker.chunks(Note(profileID: .technical, markdown: text))
        XCTAssertEqual(normalized.map(\.text), ["# Заголовок\n\nПервый\nВторой"])
        let long = Note(profileID: .technical, markdown: String(repeating: "я", count: 600))
        let fragments = NoteChunker.chunks(long, limit: -10, overlap: Int.max)
        XCTAssertTrue(fragments.allSatisfy { !$0.text.isEmpty && $0.text.count <= 200 })
        XCTAssertLessThan(fragments.count, 10)
    }
}
