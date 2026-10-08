import SwiftUI
import CopilotCore

enum DesignTokens {
    static let spacing: CGFloat = 20
    static let cornerRadius: CGFloat = 13
    static let contentWidth: CGFloat = 1320
    @MainActor static var accent: Color { color(for: PreferencesStore.shared.accent) }
    @MainActor static var accentSoft: Color { accent.opacity(0.16) }
    @MainActor static var onAccent: Color { PreferencesStore.shared.accent.prefersDarkText ? .black : .white }
    static let success = color(for: .defaultColor)
    static let canvas = adaptive(dark: 0x121615, light: 0xF3F5F3)
    static let sidebar = adaptive(dark: 0x191E1C, light: 0xE9EDE9)
    static let card = adaptive(dark: 0x202624, light: 0xFFFFFF)
    static let elevated = adaptive(dark: 0x29302D, light: 0xF7F9F7)
    static let inputBorder = adaptive(dark: 0x3A4541, light: 0xC9D0CB)
    static let hairline = adaptive(dark: 0x313936, light: 0xDDE2DE)

    static func color(for accent: AppAccent) -> Color {
        Color(red: accent.red, green: accent.green, blue: accent.blue)
    }

    static func colorBinding(_ value: Binding<AppAccent>) -> Binding<Color> {
        Binding(get: { color(for: value.wrappedValue) }, set: { newColor in
            guard let color = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            let components = [color.redComponent, color.greenComponent, color.blueComponent]
            guard components.allSatisfy(\.isFinite) else { return }
            let bytes = components.map { UInt32((min(1, max(0, $0)) * 255).rounded()) }
            value.wrappedValue = AppAccent(rgb: bytes[0] << 16 | bytes[1] << 8 | bytes[2])
        })
    }

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct InfoCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(DesignTokens.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.card, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .strokeBorder(DesignTokens.hairline, lineWidth: 1))
    }
}

struct HMPanel<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.card, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
            .strokeBorder(DesignTokens.hairline, lineWidth: 1))
    }
}

struct HMSectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 25, weight: .bold))
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HMStatusPill: View {
    let text: String
    var color: Color = DesignTokens.success
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct HMPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(DesignTokens.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HMColorPicker: View {
    let title: String
    @Binding var value: AppAccent
    @State private var hex = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ColorPicker(title, selection: DesignTokens.colorBinding($value), supportsOpacity: false)
                TextField("#RRGGBB", text: $hex)
                    .font(.system(.caption, design: .monospaced)).frame(width: 92)
                    .accessibilityLabel("\(title), RGB")
                    .onSubmit { applyHex() }
                Button("Применить") { applyHex() }.disabled(AppAccent(hex: hex) == nil || AppAccent(hex: hex) == value)
            }
            if !hex.isEmpty, AppAccent(hex: hex) == nil {
                Text("Введите шесть шестнадцатеричных цифр, например #40F0A3.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { hex = value.hex }
        .onChange(of: value) { _, newValue in hex = newValue.hex }
    }

    private func applyHex() {
        guard let color = AppAccent(hex: hex) else { return }
        value = color
        hex = color.hex
    }
}
