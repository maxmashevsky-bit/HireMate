import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct ScreenshotView: View {
    @Bindable var app: AppModel
    var body: some View {
        @Bindable var screen = app.screenshot
        VStack(alignment: .leading, spacing: 12) {
            Text("Снимок для текущего вопроса").font(.title2.bold())
            Text("Выберите дисплей или окно. Прямоугольную область можно оставить обрезкой в предпросмотре. Автоматического захвата нет.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Обновить источники") { screen.loadSources() }.disabled(screen.isBusy)
                Picker("Источник", selection: $screen.selectedSourceID) {
                    Text("Не выбран").tag(Optional<String>.none)
                    ForEach(screen.sources) { Text($0.label).tag(Optional($0.id)) }
                }
                Button("Сделать снимок") { screen.capture() }.disabled(screen.isBusy || screen.selectedSourceID == nil)
            }
            HStack {
                Picker("Формат", selection: $screen.format) { ForEach(ScreenshotEncoding.allCases) { Text($0.title).tag($0) } }.disabled(screen.isBusy)
                Button("Открыть разрешения") { _ = app.permissions.openSettings(screen: true) }
            }
            if let attachment = screen.attachment, let image = NSImage(data: attachment.data) {
                ScreenshotCanvas(image: image, pixelSize: CGSize(width: CGFloat(attachment.width), height: CGFloat(attachment.height)), selection: $screen.selection)
                    .frame(minHeight: 240, maxHeight: .infinity).background(.black.opacity(0.08))
                HStack {
                    Text("\(attachment.width)×\(attachment.height) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))").font(.caption)
                    Spacer()
                    Button("Обрезать по выделению") { screen.applyCrop() }.disabled(screen.selection == nil)
                    Button("Закрасить выделение") { screen.applyRedaction() }.disabled(screen.selection == nil)
                    Button("Удалить снимок", role: .destructive) { screen.clear() }
                }
                Toggle("Я просмотрел изображение: именно эти данные можно приложить к вопросу", isOn: $screen.reviewed)
                HStack {
                    Button("Приложить к текущему вопросу") {
                        if app.conversation.attach(attachment) { screen.clear() }
                    }.buttonStyle(.borderedProminent).disabled(!screen.reviewed || app.conversation.isGenerating || app.conversation.isLoading)
                    Text("После ответа снимок не сохраняется. Для повторной отправки сделайте новый.").font(.caption)
                }
            } else {
                ContentUnavailableView("Снимка пока нет", systemImage: "rectangle.dashed", description: Text("Захват экрана не запускается при открытии раздела."))
            }
            if screen.isBusy { ProgressView() }
            Text(screen.status).font(.caption).foregroundStyle(.secondary)
        }.padding().navigationTitle("Снимок экрана")
            .onChange(of: screen.format) { _, _ in screen.changeEncoding() }
    }
}

@MainActor
private struct ScreenshotCanvas: View {
    let image: NSImage
    let pixelSize: CGSize
    @Binding var selection: CGRect?
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / pixelSize.width, geometry.size.height / pixelSize.height)
            let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
            let origin = CGPoint(x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: size.width, height: size.height)
                if let selection {
                    Rectangle().stroke(.orange, lineWidth: 2).background(.orange.opacity(0.15))
                        .frame(width: selection.width * size.width, height: selection.height * size.height)
                        .offset(x: selection.minX * size.width, y: selection.minY * size.height)
                }
            }
            .frame(width: size.width, height: size.height).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                func clamp(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
                }
                let first = clamp(value.startLocation); let end = clamp(value.location)
                selection = CGRect(x: min(first.x, end.x), y: min(first.y, end.y), width: abs(end.x - first.x), height: abs(end.y - first.y))
            })
            .offset(x: origin.x, y: origin.y)
        }
    }
}
