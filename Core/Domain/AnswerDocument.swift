import Foundation

/// Небольшое подмножество Markdown: абзацы, ATX-заголовки, fenced code.
/// Незакрытый блок кода остаётся видимым во время потоковой генерации.
public enum AnswerDocument {
    public enum Kind: Equatable, Sendable { case text, heading(Int), code(String) }
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
        for line in lines {
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
}
