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
                    Text(inline(block.text)).font(level <= 2 ? .title3 : .headline).fontWeight(.semibold).textSelection(.enabled)
                case .code(let language):
                    AnswerCodeBlock(code: block.text, language: language)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ text: String) -> AttributedString {
        var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Ссылки остаются текстом: содержимое ответа не запускает внешние приложения.
        let links = value.runs.filter { $0.link != nil }.map(\.range)
        for range in links { value[range].link = nil }
        return value
    }
}

private struct AnswerCodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.isEmpty ? "Код" : language).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Скопировано" : "Копировать код", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(code, forType: .string)
                }.buttonStyle(.borderless)
            }
            ScrollView(.horizontal) {
                Text(verbatim: code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(12).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2)))
            .onChange(of: code) { _, _ in copied = false }
    }
}
