import SwiftUI

enum DesignTokens {
    static let spacing: CGFloat = 20
    static let cornerRadius: CGFloat = 14
    static let contentWidth: CGFloat = 1180
    static let accent = Color(red: 0, green: 0.78, blue: 0.83)
    static let canvas = adaptive(dark: 0x292627, light: 0xF5F5F7)
    static let sidebar = adaptive(dark: 0x302E2F, light: 0xECECEE)
    static let card = adaptive(dark: 0x1E1E1E, light: 0xFFFFFF)
    static let inputBorder = adaptive(dark: 0x444444, light: 0xC9C9CD)

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
    }
}
