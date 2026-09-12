import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct AttachmentPreview: View {
    @Bindable var conversation: ConversationModel
    var body: some View {
        if let attachment = conversation.attachment {
            HStack(alignment: .top) {
                if let image = NSImage(data: attachment.data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 140, height: 90)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Снимок к следующему вопросу").font(.caption.bold())
                    Text("\(attachment.width)×\(attachment.height) · только в памяти").font(.caption2)
                    Text("Демо не анализирует изображение.").font(.caption2).foregroundStyle(.secondary)
                    Button("Убрать снимок", role: .destructive) { conversation.removeAttachment() }
                }
            }.padding(8).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
