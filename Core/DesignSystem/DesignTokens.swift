import SwiftUI

enum DesignTokens {
    static let spacing: CGFloat = 20
    static let cornerRadius: CGFloat = 13
    static let contentWidth: CGFloat = 1320
    static let accent = Color(red: 0.25, green: 0.94, blue: 0.64)
    static let accentSoft = Color(red: 0.25, green: 0.94, blue: 0.64).opacity(0.16)
    static let success = accent
    static let canvas = adaptive(dark: 0x121615, light: 0xF3F5F3)
    static let sidebar = adaptive(dark: 0x191E1C, light: 0xE9EDE9)
    static let card = adaptive(dark: 0x202624, light: 0xFFFFFF)
    static let elevated = adaptive(dark: 0x29302D, light: 0xF7F9F7)
    static let inputBorder = adaptive(dark: 0x3A4541, light: 0xC9D0CB)
    static let hairline = adaptive(dark: 0x313936, light: 0xDDE2DE)

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
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
