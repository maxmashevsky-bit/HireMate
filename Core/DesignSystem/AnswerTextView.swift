import AppKit
import SwiftUI
import CopilotCore

struct AnswerTextView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(AnswerDocument.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .text:
                    Text(inline(block.text)).textSelection(.enabled).lineSpacing(4)
                case .heading(let level):
                    Text(inline(block.text))
                        .font(.system(size: PreferencesStore.shared.messageFontSize * (level <= 2 ? 1.25 : 1.1), weight: .semibold))
                        .textSelection(.enabled)
                case .code(let language):
                    AnswerCodeBlock(code: block.text, language: language)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.marker).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(minWidth: 22, alignment: .trailing)
                                Text(inline(item.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                        Text(inline(block.text)).textSelection(.enabled).lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                case .horizontalRule:
                    Divider().padding(.vertical, 6)
                case .table(let table):
                    tableView(table)
                }
            }
        }.font(.system(size: PreferencesStore.shared.messageFontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ text: String) -> AttributedString {
        var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Ссылки остаются текстом: содержимое ответа не запускает внешние приложения.
        let links = value.runs.filter { $0.link != nil }.map(\.range)
        for range in links { value[range].link = nil }
        return value
    }

    private func tableView(_ table: AnswerDocument.Table) -> some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0) {
                tableRow(table.headers, table: table, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row, table: table, isHeader: false)
                }
            }.fixedSize(horizontal: true, vertical: false)
                .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
        }.accessibilityLabel("Таблица, \(table.headers.count) столбцов, \(table.rows.count) строк")
    }
    private func tableRow(_ cells: [String], table: AnswerDocument.Table, isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                let column = table.alignments[index]
                Text(inline(cell)).fontWeight(isHeader ? .semibold : .regular)
                    .textSelection(.enabled).lineSpacing(3)
                    .multilineTextAlignment(column == .center ? .center : (column == .trailing ? .trailing : .leading))
                    .frame(width: 180, alignment: column == .center ? .center : (column == .trailing ? .trailing : .leading))
                    .fixedSize(horizontal: false, vertical: true).padding(10)
            }
        }
    }
}

private struct AnswerCodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false
    @State private var expanded = false
    @State private var contentHeight: CGFloat = 40
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.isEmpty ? "Код" : language).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if contentHeight > 240 {
                    Button(expanded ? "Свернуть код" : "Развернуть код",
                           systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        expanded.toggle()
                    }.buttonStyle(.borderless)
                }
                Button(copied ? "Скопировано" : "Копировать код", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(code, forType: .string)
                }.buttonStyle(.borderless)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(highlightedCode)
                    .font(.system(size: PreferencesStore.shared.messageFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = max(40, height + 8)
                    }
            }
            .frame(height: expanded ? contentHeight : min(240, contentHeight))
        }.padding(12).background(DesignTokens.color(for: PreferencesStore.shared.codeTheme.background), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2)))
            .preferredColorScheme(.dark)
            .onChange(of: code) { _, _ in copied = false }
    }

    private var highlightedCode: AttributedString {
        let preferences = PreferencesStore.shared
        guard preferences.syntaxHighlighting else {
            var plain = AttributedString(code)
            plain.foregroundColor = DesignTokens.color(for: preferences.codeTheme.color(for: .plain))
            return plain
        }
        var result = AttributedString()
        for token in AnswerDocument.codeTokens(code, language: language) {
            var part = AttributedString(token.text)
            part.foregroundColor = DesignTokens.color(for: preferences.codeTheme.color(for: token.kind))
            result.append(part)
        }
        return result
    }
}
