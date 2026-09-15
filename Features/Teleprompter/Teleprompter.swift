import AppKit
import Observation
import SwiftUI

enum TeleprompterPosition: String, CaseIterable, Identifiable {
    case top, center, bottom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: "Сверху"
        case .center: "По центру"
        case .bottom: "Снизу"
        }
    }
}

enum TeleprompterContentSource: String, CaseIterable, Identifiable {
    case custom, lastAnswer, question
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: "Свой текст"
        case .lastAnswer: "Последний ответ"
        case .question: "Текущий вопрос"
        }
    }
}

@MainActor @Observable
final class TeleprompterModel {
    private let defaults: UserDefaults
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    var text: String { didSet { defaults.set(text, forKey: "teleprompter.text"); clampIndex() } }
    var fontSize: Double { didSet { defaults.set(min(72, max(18, fontSize)), forKey: "teleprompter.fontSize") } }
    var opacity: Double { didSet { defaults.set(min(1, max(0.35, opacity)), forKey: "teleprompter.opacity") } }
    var speed: Double { didSet { defaults.set(min(300, max(30, speed)), forKey: "teleprompter.speed"); restartIfPlaying() } }
    var position: TeleprompterPosition { didSet { defaults.set(position.rawValue, forKey: "teleprompter.position") } }
    var source: TeleprompterContentSource { didSet { defaults.set(source.rawValue, forKey: "teleprompter.source") } }
    private(set) var activeWordIndex = 0
    private(set) var isPlaying = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: "teleprompter.text") ?? ""
        let savedFont = defaults.object(forKey: "teleprompter.fontSize") as? Double ?? 34
        fontSize = savedFont.isFinite ? min(72, max(18, savedFont)) : 34
        let savedOpacity = defaults.object(forKey: "teleprompter.opacity") as? Double ?? 0.85
        opacity = savedOpacity.isFinite ? min(1, max(0.35, savedOpacity)) : 0.85
        let savedSpeed = defaults.object(forKey: "teleprompter.speed") as? Double ?? 120
        speed = savedSpeed.isFinite ? min(300, max(30, savedSpeed)) : 120
        position = TeleprompterPosition(rawValue: defaults.string(forKey: "teleprompter.position") ?? "") ?? .top
        source = TeleprompterContentSource(rawValue: defaults.string(forKey: "teleprompter.source") ?? "") ?? .lastAnswer
    }

    var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }

    func updateContent(from app: AppModel) {
        switch source {
        case .custom: break
        case .lastAnswer: text = app.answer
        case .question: text = app.question
        }
        reset()
    }

    func togglePlayback() {
        guard !words.isEmpty else { return }
        isPlaying.toggle()
        if isPlaying { scheduleNextWord() } else { playbackTask?.cancel() }
    }

    func reset() {
        playbackTask?.cancel()
        isPlaying = false
        activeWordIndex = 0
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func clampIndex() {
        activeWordIndex = min(activeWordIndex, max(0, words.count - 1))
        if words.isEmpty { stop() }
    }

    private func restartIfPlaying() {
        guard isPlaying else { return }
        playbackTask?.cancel()
        scheduleNextWord()
    }

    private func scheduleNextWord() {
        playbackTask?.cancel()
        let interval = 60 / min(300, max(30, speed))
        playbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self, self.isPlaying else { return }
            if self.activeWordIndex + 1 < self.words.count {
                self.activeWordIndex += 1
                self.scheduleNextWord()
            } else {
                self.isPlaying = false
                self.playbackTask = nil
            }
        }
    }
}

@MainActor
private final class TeleprompterPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

@MainActor @Observable
final class TeleprompterController: NSObject, NSWindowDelegate {
    let settings = TeleprompterModel()
    private weak var app: AppModel?
    private var panel: TeleprompterPanel?
    private(set) var isVisible = false
    private(set) var isClickThrough = false

    func connect(app: AppModel) { self.app = app }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let app else { return }
        if settings.source != .custom { settings.updateContent(from: app) }
        if panel == nil {
            let panel = TeleprompterPanel(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 430),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.sharingType = .none
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: TeleprompterView(app: app, model: settings, controller: self))
            self.panel = panel
        }
        applyOpacity()
        applyPosition()
        panel?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        settings.stop()
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggleClickThrough() {
        isClickThrough.toggle()
        panel?.ignoresMouseEvents = isClickThrough
    }

    func applyOpacity() { panel?.alphaValue = min(1, max(0.35, settings.opacity)) }

    func applyPosition() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y: CGFloat
        switch settings.position {
        case .top: y = visible.maxY - panel.frame.height - 24
        case .center: y = visible.midY - panel.frame.height / 2
        case .bottom: y = visible.minY + 24
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowWillClose(_ notification: Notification) { hide() }
    func shutdown() { settings.stop(); panel?.sharingType = .readOnly; panel?.close(); panel = nil; isVisible = false }
}

@MainActor
private struct TeleprompterView: View {
    @Bindable var app: AppModel
    @Bindable var model: TeleprompterModel
    @Bindable var controller: TeleprompterController
    @State private var settingsVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Телесуфлёр", systemImage: "text.viewfinder")
                Spacer()
                Text("\(model.words.isEmpty ? 0 : model.activeWordIndex + 1)/\(model.words.count)")
                    .foregroundStyle(.secondary)
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }.disabled(model.words.isEmpty).help(model.isPlaying ? "Пауза" : "Продолжить")
                Button { settingsVisible.toggle() } label: { Image(systemName: "gearshape") }.help("Настройки")
                Button { controller.hide() } label: { Image(systemName: "xmark") }.help("Скрыть телесуфлёр")
            }
            .buttonStyle(.borderless).padding(12)
            Divider()
            wordPreview
            if settingsVisible {
                Divider()
                settingsTabs.frame(height: 190)
            }
        }
        .frame(minWidth: 620, minHeight: settingsVisible ? 390 : 190)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.35)))
        .onChange(of: model.opacity) { _, _ in controller.applyOpacity() }
        .onChange(of: model.position) { _, _ in controller.applyPosition() }
    }

    private var wordPreview: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(model.words.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.system(size: model.fontSize, weight: index == model.activeWordIndex ? .bold : .regular))
                            .foregroundStyle(index == model.activeWordIndex ? Color.orange : .primary.opacity(0.62))
                            .id(index)
                    }
                }.padding(.horizontal, 28).frame(minHeight: 120)
            }
            .onChange(of: model.activeWordIndex) { _, index in withAnimation { proxy.scrollTo(index, anchor: .center) } }
        }
    }

    private var settingsTabs: some View {
        TabView {
            Form {
                Slider(value: $model.fontSize, in: 18...72) { Text("Размер текста") }
                Slider(value: $model.opacity, in: 0.35...1) { Text("Непрозрачность") }
            }.tabItem { Text("Внешний вид") }
            TextEditor(text: $model.text).font(.body.monospaced()).padding(8)
                .tabItem { Text("Текст") }
            Form {
                Picker("Расположение", selection: $model.position) {
                    ForEach(TeleprompterPosition.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("Окно можно перетянуть за фон.").foregroundStyle(.secondary)
            }.tabItem { Text("Расположение") }
            Form {
                Slider(value: $model.speed, in: 30...300, step: 5) { Text("Слов в минуту") }
                HStack {
                    Button(model.isPlaying ? "Пауза" : "Продолжить") { model.togglePlayback() }.disabled(model.words.isEmpty)
                    Button("Сначала") { model.reset() }
                }
            }.tabItem { Text("Прокрутка") }
            Form {
                Picker("Источник", selection: $model.source) {
                    ForEach(TeleprompterContentSource.allCases) { Text($0.title).tag($0) }
                }
                Button("Обновить содержимое") { model.updateContent(from: app) }
                Toggle("Пропускать клики сквозь окно", isOn: Binding(
                    get: { controller.isClickThrough }, set: { _ in controller.toggleClickThrough() }
                ))
            }.tabItem { Text("Содержимое") }
        }.padding(8)
    }
}
