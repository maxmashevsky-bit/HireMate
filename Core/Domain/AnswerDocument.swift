import Foundation

/// Подмножество Markdown для локального просмотра заметок и потоковых ответов.
/// Незакрытый блок кода остаётся видимым во время потоковой генерации.
public enum AnswerDocument {
    public enum SyntaxKind: Equatable, Sendable { case plain, keyword, string, comment, number }
    public struct SyntaxToken: Equatable, Sendable {
        public let text: String
        public let kind: SyntaxKind
    }

    /// Лексическая подсветка Go без изменения или исполнения исходного текста.
    public static func codeTokens(_ source: String, language: String) -> [SyntaxToken] {
        guard ["go", "golang"].contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
              source.utf8.count <= 128_000 else { return [SyntaxToken(text: source, kind: .plain)] }
        let keywords: Set<String> = ["break", "default", "func", "interface", "select", "case", "defer", "go", "map", "struct",
            "chan", "else", "goto", "package", "switch", "const", "fallthrough", "if", "range", "type", "continue", "for", "import", "return", "var"]
        var result: [SyntaxToken] = []
        var cursor = source.startIndex
        var plainStart = cursor
        while cursor < source.endIndex {
            let start = cursor
            let first = source[cursor]
            cursor = source.index(after: cursor)
            var kind = SyntaxKind.plain
            if first == "/", cursor < source.endIndex, source[cursor] == "/" {
                kind = .comment
                while cursor < source.endIndex, !source[cursor].isNewline { cursor = source.index(after: cursor) }
            } else if first == "/", cursor < source.endIndex, source[cursor] == "*" {
                kind = .comment
                cursor = source.index(after: cursor)
                while cursor < source.endIndex {
                    let character = source[cursor]
                    cursor = source.index(after: cursor)
                    if character == "*", cursor < source.endIndex, source[cursor] == "/" {
                        cursor = source.index(after: cursor); break
                    }
                }
            } else if first == "\"" || first == "'" || first == "`" {
                kind = .string
                while cursor < source.endIndex {
                    let character = source[cursor]
                    cursor = source.index(after: cursor)
                    if character == first { break }
                    if first != "`", character == "\\", cursor < source.endIndex { cursor = source.index(after: cursor) }
                }
            } else if first.isLetter || first == "_" {
                while cursor < source.endIndex, source[cursor].isLetter || source[cursor].isNumber || source[cursor] == "_" {
                    cursor = source.index(after: cursor)
                }
                if keywords.contains(String(source[start..<cursor])) { kind = .keyword }
            } else if first.isNumber {
                kind = .number
                var previous = first
                while cursor < source.endIndex {
                    let character = source[cursor]
                    let exponentSign = (character == "+" || character == "-") && (previous == "e" || previous == "E")
                    guard character.isNumber || "abcdefABCDEFxXoObB_.".contains(character) || exponentSign else { break }
                    previous = character
                    cursor = source.index(after: cursor)
                }
            }
            if kind != .plain {
                if plainStart < start { result.append(SyntaxToken(text: String(source[plainStart..<start]), kind: .plain)) }
                result.append(SyntaxToken(text: String(source[start..<cursor]), kind: kind))
                plainStart = cursor
            }
        }
        if plainStart < source.endIndex { result.append(SyntaxToken(text: String(source[plainStart...]), kind: .plain)) }
        return result
    }

    public struct ListItem: Equatable, Sendable {
        public let marker: String
        public let text: String
    }
    public enum ColumnAlignment: Equatable, Sendable { case leading, center, trailing }
    public struct Table: Equatable, Sendable {
        public let headers: [String]
        public let alignments: [ColumnAlignment]
        public let rows: [[String]]
    }
    public enum Kind: Equatable, Sendable {
        case text, heading(Int), code(String), list([ListItem]), quote, table(Table), horizontalRule
    }
    public struct Block: Equatable, Sendable {
        public let kind: Kind
        public let text: String
    }
    public static func blocks(_ source: String) -> [Block] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: Character?
        var fenceLength = 0
        var language = ""
        func flushParagraph() {
            if !paragraph.isEmpty { result.append(Block(kind: .text, text: paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let indentation = line.prefix { $0 == " " }.count
            let trimmed = indentation <= 3 ? String(line.dropFirst(indentation)) : line
            if let marker = fence {
                let run = trimmed.prefix { $0 == marker }.count
                if run >= fenceLength && trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(Block(kind: .code(language), text: code.joined(separator: "\n")))
                    code = []; fence = nil
                } else { code.append(line) }
                continue
            }
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix { $0 == first }.count
                let info = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
                if count >= 3 && !(first == "`" && info.contains("`")) {
                    flushParagraph(); fence = first; fenceLength = count
                    language = String(info.prefix(40)); continue
                }
            }
            if isHorizontalRule(trimmed) {
                flushParagraph()
                result.append(Block(kind: .horizontalRule, text: line))
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted = [quoteText(trimmed)]
                while index < lines.count {
                    let next = blockLine(lines[index])
                    guard next.hasPrefix(">") else { break }
                    quoted.append(quoteText(next)); index += 1
                }
                result.append(Block(kind: .quote, text: quoted.joined(separator: "\n")))
                continue
            }
            if let first = listItem(trimmed) {
                flushParagraph()
                var items = [first.item]
                var original = [line]
                while index < lines.count, !isHorizontalRule(blockLine(lines[index])),
                      let next = listItem(blockLine(lines[index])), next.ordered == first.ordered {
                    items.append(next.item); original.append(lines[index]); index += 1
                }
                result.append(Block(kind: .list(items), text: original.joined(separator: "\n")))
                continue
            }
            if index < lines.count, let headers = tableCells(trimmed), headers.count <= 32,
               let delimiters = tableCells(blockLine(lines[index])), delimiters.count == headers.count,
               let alignments = tableAlignments(delimiters) {
                flushParagraph()
                var original = [line, lines[index]]
                index += 1
                var rows: [[String]] = []
                while index < lines.count, let cells = tableCells(blockLine(lines[index])), cells.count == headers.count {
                    rows.append(cells); original.append(lines[index]); index += 1
                }
                result.append(Block(kind: .table(Table(headers: headers, alignments: alignments, rows: rows)),
                                    text: original.joined(separator: "\n")))
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                result.append(Block(kind: .heading(hashes), text: String(trimmed.dropFirst(hashes + 1))))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else { paragraph.append(line) }
        }
        if fence != nil { result.append(Block(kind: .code(language), text: code.joined(separator: "\n"))) }
        flushParagraph()
        return result
    }

    private static func blockLine(_ line: String) -> String {
        let count = line.prefix { $0 == " " }.count
        return count <= 3 ? String(line.dropFirst(count)) : line
    }
    private static func quoteText(_ line: String) -> String {
        let content = line.dropFirst()
        return String(content.first == " " ? content.dropFirst() : content)
    }
    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.prefix(while: { $0 == " " }).count <= 3 else { return false }
        let markers = line.filter { $0 != " " && $0 != "\t" }
        guard markers.count >= 3, let first = markers.first, "-*_".contains(first) else { return false }
        return markers.allSatisfy { $0 == first }
    }
    private static func listItem(_ line: String) -> (item: ListItem, ordered: Bool)? {
        guard let first = line.first else { return nil }
        if "-*+".contains(first), line.dropFirst().first == " " || line.dropFirst().first == "\t" {
            return (ListItem(marker: "•", text: String(line.dropFirst(2))), false)
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let suffix = line.dropFirst(digits.count)
        guard suffix.first == "." || suffix.first == ")",
              suffix.dropFirst().first == " " || suffix.dropFirst().first == "\t" else { return nil }
        return (ListItem(marker: String(digits) + String(suffix.prefix(1)), text: String(suffix.dropFirst(2))), true)
    }
    private static func tableCells(_ line: String) -> [String]? {
        guard line.prefix(while: { $0 == " " }).count <= 3 else { return nil }
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.contains("|") else { return nil }
        var cells: [String] = []
        var cell = ""
        var cursor = value.startIndex
        var codeFence = 0
        var lastWasDelimiter = false
        var delimiterCount = 0
        while cursor < value.endIndex {
            let character = value[cursor]
            cursor = value.index(after: cursor)
            lastWasDelimiter = false
            if character == "\\", cursor < value.endIndex {
                let next = value[cursor]
                if next == "|" || next == "\\" {
                    cell += next == "|" ? "|" : "\\\\"
                    cursor = value.index(after: cursor); continue
                }
            }
            if character == "`" {
                var run = 1
                while cursor < value.endIndex, value[cursor] == "`" { run += 1; cursor = value.index(after: cursor) }
                if codeFence == 0 { codeFence = run } else if codeFence == run { codeFence = 0 }
                cell += String(repeating: "`", count: run); continue
            }
            if character == "|", codeFence == 0 {
                delimiterCount += 1
                cells.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""; lastWasDelimiter = true
            } else { cell.append(character) }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if value.hasPrefix("|"), cells.first == "" { cells.removeFirst() }
        if lastWasDelimiter, cells.last == "" { cells.removeLast() }
        return cells.isEmpty || delimiterCount == 0 ? nil : cells
    }
    private static func tableAlignments(_ cells: [String]) -> [ColumnAlignment]? {
        var result: [ColumnAlignment] = []
        for cell in cells {
            let leading = cell.hasPrefix(":")
            let trailing = cell.hasSuffix(":")
            var marker = cell[...]
            if leading { marker = marker.dropFirst() }
            if trailing, !marker.isEmpty { marker = marker.dropLast() }
            guard marker.count >= 3, marker.allSatisfy({ $0 == "-" }) else { return nil }
            result.append(leading && trailing ? .center : (trailing ? .trailing : .leading))
        }
        return result
    }
}
