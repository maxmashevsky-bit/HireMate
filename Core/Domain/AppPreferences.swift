import Foundation

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

/// Только несекретные UI-настройки. Доменные данные будут храниться в SQLite.
@MainActor
public final class PreferencesStore {
    public static let allowedKeys = ["ui.theme", "ui.profile", "ui.onboardingCompleted"]
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
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

