import Foundation
import Observation

public struct AppAccent: Hashable, Sendable {
    public static let defaultColor = AppAccent(rgb: 0x40F0A3)
    public let rgb: UInt32

    public init(rgb: UInt32) { self.rgb = rgb & 0xFFFFFF }

    public init?(hex: String) {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    public var hex: String { String(format: "#%06X", rgb) }
    public var red: Double { Double((rgb >> 16) & 255) / 255 }
    public var green: Double { Double((rgb >> 8) & 255) / 255 }
    public var blue: Double { Double(rgb & 255) / 255 }

    public var prefersDarkText: Bool {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }
}

public enum AppTheme: String, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "Как в macOS"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

public enum CodeColorTheme: String, CaseIterable, Sendable, Identifiable {
    case githubDark, xcodeDark, monokai
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .githubDark: "GitHub Dark"
        case .xcodeDark: "Xcode Dark"
        case .monokai: "Monokai"
        }
    }
    public var background: AppAccent {
        AppAccent(rgb: self == .githubDark ? 0x0D1117 : self == .xcodeDark ? 0x1F1F24 : 0x272822)
    }
    public func color(for kind: AnswerDocument.SyntaxKind) -> AppAccent {
        let palette: (plain: UInt32, keyword: UInt32, string: UInt32, comment: UInt32, number: UInt32)
        switch self {
        case .githubDark: palette = (0xC9D1D9, 0xFF7B72, 0xA5D6FF, 0x8B949E, 0x79C0FF)
        case .xcodeDark: palette = (0xE0E0E0, 0xFC5FA3, 0xFC6A5D, 0x9AA99A, 0xD0BF69)
        case .monokai: palette = (0xF8F8F2, 0xF92672, 0xE6DB74, 0xA5A591, 0xAE81FF)
        }
        let rgb: UInt32
        switch kind {
        case .plain: rgb = palette.plain
        case .keyword: rgb = palette.keyword
        case .string: rgb = palette.string
        case .comment: rgb = palette.comment
        case .number: rgb = palette.number
        }
        return AppAccent(rgb: rgb)
    }
}

public enum MessageOrder: String, CaseIterable, Sendable, Identifiable {
    case newestBottom, newestTop
    public var id: String { rawValue }
    public var title: String { self == .newestBottom ? "Новые снизу" : "Новые сверху" }
}

/// Только несекретные UI-настройки. Доменные данные хранятся в SQLite.
@MainActor @Observable
public final class PreferencesStore {
    public static let shared = PreferencesStore()
    public static let allowedKeys = ["ui.theme", "ui.profile", "ui.onboardingCompleted", "ui.accent", "ui.messageFontSize", "ui.retainCancelledAnswer", "ui.cancelGenerationOnSend", "ui.codeTheme", "ui.syntaxHighlighting", "ui.messageOrder", "ui.collapseAnswers", "ui.collapseLatestAnswer", "ui.collapseTranscripts", "ui.collapseLatestTranscript", "audio.inputMode", "audio.questionMode", "audio.configuration"]
    private let defaults: UserDefaults
    public var audioInputMode: AudioInputMode {
        didSet { defaults.set(audioInputMode.rawValue, forKey: "audio.inputMode") }
    }
    public var audioQuestionMode: AudioQuestionMode {
        didSet { defaults.set(audioQuestionMode.rawValue, forKey: "audio.questionMode") }
    }
    private var storedAudioConfiguration: AudioPipelineConfiguration
    public var audioConfiguration: AudioPipelineConfiguration {
        get { storedAudioConfiguration }
        set {
            storedAudioConfiguration = newValue.bounded()
            if let data = try? JSONEncoder().encode(storedAudioConfiguration) {
                defaults.set(data, forKey: "audio.configuration")
            }
        }
    }
    public var collapseAnswers: Bool {
        didSet { defaults.set(collapseAnswers, forKey: "ui.collapseAnswers") }
    }
    public var collapseLatestAnswer: Bool {
        didSet { defaults.set(collapseLatestAnswer, forKey: "ui.collapseLatestAnswer") }
    }
    public var collapseTranscripts: Bool {
        didSet { defaults.set(collapseTranscripts, forKey: "ui.collapseTranscripts") }
    }
    public var collapseLatestTranscript: Bool {
        didSet { defaults.set(collapseLatestTranscript, forKey: "ui.collapseLatestTranscript") }
    }
    public var messageOrder: MessageOrder {
        didSet { defaults.set(messageOrder.rawValue, forKey: "ui.messageOrder") }
    }
    public var codeTheme: CodeColorTheme {
        didSet { defaults.set(codeTheme.rawValue, forKey: "ui.codeTheme") }
    }
    public var syntaxHighlighting: Bool {
        didSet { defaults.set(syntaxHighlighting, forKey: "ui.syntaxHighlighting") }
    }
    public var retainCancelledAnswer: Bool {
        didSet { defaults.set(retainCancelledAnswer, forKey: "ui.retainCancelledAnswer") }
    }
    public var cancelGenerationOnSend: Bool {
        didSet { defaults.set(cancelGenerationOnSend, forKey: "ui.cancelGenerationOnSend") }
    }
    private var storedMessageFontSize: Double
    public var messageFontSize: Double {
        get { storedMessageFontSize }
        set {
            storedMessageFontSize = Self.normalizedFontSize(newValue)
            defaults.set(storedMessageFontSize, forKey: "ui.messageFontSize")
        }
    }
    public var accent: AppAccent {
        didSet { defaults.set(accent.hex, forKey: "ui.accent") }
    }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        audioInputMode = AudioInputMode(rawValue: defaults.string(forKey: "audio.inputMode") ?? "") ?? .microphone
        audioQuestionMode = AudioQuestionMode(rawValue: defaults.string(forKey: "audio.questionMode") ?? "") ?? .manual
        storedAudioConfiguration = defaults.data(forKey: "audio.configuration")
            .flatMap { try? JSONDecoder().decode(AudioPipelineConfiguration.self, from: $0) }?.bounded()
            ?? AudioPipelineConfiguration()
        collapseAnswers = defaults.object(forKey: "ui.collapseAnswers") as? Bool ?? false
        collapseLatestAnswer = defaults.object(forKey: "ui.collapseLatestAnswer") as? Bool ?? false
        collapseTranscripts = defaults.object(forKey: "ui.collapseTranscripts") as? Bool ?? false
        collapseLatestTranscript = defaults.object(forKey: "ui.collapseLatestTranscript") as? Bool ?? false
        messageOrder = MessageOrder(rawValue: defaults.string(forKey: "ui.messageOrder") ?? "") ?? .newestBottom
        codeTheme = CodeColorTheme(rawValue: defaults.string(forKey: "ui.codeTheme") ?? "") ?? .githubDark
        syntaxHighlighting = defaults.object(forKey: "ui.syntaxHighlighting") as? Bool ?? true
        retainCancelledAnswer = defaults.object(forKey: "ui.retainCancelledAnswer") as? Bool ?? true
        cancelGenerationOnSend = defaults.object(forKey: "ui.cancelGenerationOnSend") as? Bool ?? false
        storedMessageFontSize = Self.normalizedFontSize(defaults.object(forKey: "ui.messageFontSize") as? Double ?? 13.5)
        accent = defaults.string(forKey: "ui.accent").flatMap(AppAccent.init(hex:)) ?? .defaultColor
    }
    private static func normalizedFontSize(_ value: Double) -> Double {
        value.isFinite ? min(22, max(11, value)) : 13.5
    }
    public var theme: AppTheme {
        get { AppTheme(rawValue: defaults.string(forKey: "ui.theme") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "ui.theme") }
    }
    public var profile: ProfileID {
        get { ProfileID(rawValue: defaults.string(forKey: "ui.profile") ?? "") ?? .liveCoding }
        set { defaults.set(newValue.rawValue, forKey: "ui.profile") }
    }
    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "ui.onboardingCompleted") }
        set { defaults.set(newValue, forKey: "ui.onboardingCompleted") }
    }
}
