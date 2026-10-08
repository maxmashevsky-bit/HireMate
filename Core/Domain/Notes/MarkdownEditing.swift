import Foundation

public enum MarkdownFormat: String, CaseIterable, Identifiable, Sendable {
    case bold, italic, strikethrough, link, inlineCode, codeBlock, heading1, heading2, heading3
    case bulletList, numberedList, quote, horizontalRule, table
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bold: "Жирный"
        case .italic: "Курсив"
        case .strikethrough: "Зачёркнутый"
        case .link: "Ссылка"
        case .inlineCode: "Код в строке"
        case .codeBlock: "Блок кода"
        case .heading1: "Заголовок 1"
        case .heading2: "Заголовок 2"
        case .heading3: "Заголовок 3"
        case .bulletList: "Маркированный список"
        case .numberedList: "Нумерованный список"
        case .quote: "Цитата"
        case .horizontalRule: "Разделитель"
        case .table: "Таблица"
        }
    }
}

public struct MarkdownEdit: Sendable, Equatable {
    public let text: String
    public let selection: NSRange
}

public enum MarkdownEditing {
    public static func apply(_ format: MarkdownFormat, to text: String, selection: NSRange? = nil) -> MarkdownEdit? {
        guard text.utf8.count <= 1_048_576 else { return nil }
        let length = text.utf16.count
        var target = selection ?? NSRange(location: length, length: 0)
        guard target.location >= 0, target.length >= 0, target.location <= length, target.length <= length - target.location,
              let range = Range(target, in: text) else { return nil }
        let source = text as NSString
        if target.length > 0 {
            guard source.rangeOfComposedCharacterSequences(for: target) == target else { return nil }
        } else if target.location < length {
            guard source.rangeOfComposedCharacterSequence(at: target.location).location == target.location else { return nil }
        }
        let selected = String(text[range])
        var replacement: String
        var inner: NSRange
        switch format {
        case .bold, .italic, .strikethrough:
            let marker = format == .bold ? "**" : (format == .italic ? "*" : "~~")
            let markerLength = marker.utf16.count
            if selected.count >= marker.count * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
                replacement = String(selected.dropFirst(marker.count).dropLast(marker.count))
                inner = NSRange(location: 0, length: replacement.utf16.count)
            } else if target.location >= markerLength, target.location + target.length + markerLength <= length,
                      (text as NSString).substring(with: NSRange(location: target.location - markerLength, length: markerLength)) == marker,
                      (text as NSString).substring(with: NSRange(location: target.location + target.length, length: markerLength)) == marker {
                target = NSRange(location: target.location - markerLength, length: target.length + 2 * markerLength)
                replacement = selected
                inner = NSRange(location: 0, length: selected.utf16.count)
            } else {
                let body = selected.isEmpty ? "текст" : selected
                replacement = marker + body + marker
                inner = NSRange(location: markerLength, length: body.utf16.count)
            }
        case .link:
            let body = selected.isEmpty ? "текст ссылки" : selected
            replacement = "[" + body + "](https://example.com)"
            inner = NSRange(location: body.utf16.count + 3, length: "https://example.com".utf16.count)
        case .inlineCode:
            let body = selected.isEmpty ? "код" : selected
            guard !body.contains(where: \.isNewline) else { return nil }
            var longest = 0
            var run = 0
            for character in body {
                run = character == "`" ? run + 1 : 0
                longest = max(longest, run)
            }
            let fence = String(repeating: "`", count: longest + 1)
            let padding = body.hasPrefix("`") || body.hasSuffix("`") ||
                (body.hasPrefix(" ") && body.hasSuffix(" ") && body.contains(where: { $0 != " " })) ? " " : ""
            let left = fence + padding
            let right = padding + fence
            if target.location >= left.utf16.count, target.location + target.length + right.utf16.count <= length,
               source.substring(with: NSRange(location: target.location - left.utf16.count, length: left.utf16.count)) == left,
               source.substring(with: NSRange(location: target.location + target.length, length: right.utf16.count)) == right {
                target = NSRange(location: target.location - left.utf16.count, length: target.length + left.utf16.count + right.utf16.count)
                replacement = selected
                inner = NSRange(location: 0, length: selected.utf16.count)
            } else {
                replacement = left + body + right
                inner = NSRange(location: left.utf16.count, length: body.utf16.count)
            }
        case .codeBlock:
            let body = selected.isEmpty ? "код" : selected
            let longestFence = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).prefix { $0 == "`" }.count }.max() ?? 0
            let fence = String(repeating: "`", count: max(3, longestFence + 1))
            let prefix = target.location > 0 && !(text as NSString).substring(to: target.location).hasSuffix("\n") ? "\n" : ""
            let suffix = target.location + target.length < length && !(text as NSString).substring(from: target.location + target.length).hasPrefix("\n") ? "\n" : ""
            replacement = prefix + fence + "\n" + body + (body.hasSuffix("\n") ? "" : "\n") + fence + suffix
            inner = NSRange(location: prefix.utf16.count + fence.utf16.count + 1, length: body.utf16.count)
        case .bulletList, .numberedList, .quote:
            target = (text as NSString).lineRange(for: target)
            let original = (text as NSString).substring(with: target)
            let trailing = original.hasSuffix("\n")
            var lines = original.components(separatedBy: "\n")
            if trailing { lines.removeLast() }
            replacement = lines.enumerated().map { index, line in
                let prefix = format == .quote ? "> " : (format == .bulletList ? "- " : "\(index + 1). ")
                return prefix + (line.isEmpty ? "текст" : line)
            }.joined(separator: "\n") + (trailing ? "\n" : "")
            inner = NSRange(location: 0, length: replacement.utf16.count)
        case .heading1, .heading2, .heading3:
            target = source.lineRange(for: target)
            let original = source.substring(with: target)
            let trailing = original.hasSuffix("\n")
            var lines = original.components(separatedBy: "\n")
            if trailing { lines.removeLast() }
            let level = format == .heading1 ? 1 : (format == .heading2 ? 2 : 3)
            let marker = String(repeating: "#", count: level) + " "
            let remove = lines.allSatisfy { $0.hasPrefix(marker) }
            replacement = lines.map { line in
                if remove { return String(line.dropFirst(marker.count)) }
                let hashes = line.prefix { $0 == "#" }.count
                let body = (1...6).contains(hashes) && line.dropFirst(hashes).first == " " ? String(line.dropFirst(hashes + 1)) : line
                return marker + (body.isEmpty ? "Заголовок" : body)
            }.joined(separator: "\n") + (trailing ? "\n" : "")
            inner = NSRange(location: 0, length: replacement.utf16.count)
        case .horizontalRule:
            let before = source.substring(to: target.location) + selected
            let prefix = before.isEmpty || before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n")
            let after = source.substring(from: target.location + target.length)
            let suffix = after.isEmpty || after.hasPrefix("\n\n") ? "" : (after.hasPrefix("\n") ? "\n" : "\n\n")
            replacement = selected + prefix + "---" + suffix
            inner = NSRange(location: selected.utf16.count + prefix.utf16.count, length: 3)
        case .table:
            let prefix = target.location > 0 && !(text as NSString).substring(to: target.location).hasSuffix("\n") ? "\n" : ""
            replacement = prefix + "| Заголовок | Значение |\n| --- | --- |\n| " + (selected.isEmpty ? "текст" : selected.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")) + " | текст |\n"
            inner = NSRange(location: prefix.utf16.count + 2, length: "Заголовок".utf16.count)
        }
        guard let replacementRange = Range(target, in: text) else { return nil }
        var updated = text
        updated.replaceSubrange(replacementRange, with: replacement)
        guard updated.utf8.count <= 1_048_576 else { return nil }
        return MarkdownEdit(text: updated, selection: NSRange(location: target.location + inner.location, length: inner.length))
    }
}
