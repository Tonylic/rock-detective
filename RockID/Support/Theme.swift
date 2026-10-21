import RockKit
import SwiftUI
import UIKit

extension Color {
    /// A color that adapts to light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Theme {
    static let lava = Color(light: 0xF2672E, dark: 0xFF8A50)
    static let ocean = Color(light: 0x1A9E8F, dark: 0x3CC7B6)
    static let grape = Color(light: 0x7E57E0, dark: 0xA88BFF)
    static let sunshine = Color(light: 0xFFC233, dark: 0xFFD166)
    static let sky = Color(light: 0x3B8EEA, dark: 0x6AAEFF)
    static let leaf = Color(light: 0x3FA34D, dark: 0x67C672)

    static let background = Color(light: 0xFFF6E6, dark: 0x1B1713)
    static let backgroundBottom = Color(light: 0xFDE7C8, dark: 0x251E17)
    static let card = Color(light: 0xFFFFFF, dark: 0x2C2620)
    static let softCard = Color(light: 0xFFF1DB, dark: 0x352D25)
    static let ink = Color(light: 0x3A2E25, dark: 0xF5ECE1)
    static let subtleInk = Color(light: 0x7A6A5C, dark: 0xC2B4A6)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [background, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    static func color(for family: RockFamily) -> Color {
        switch family {
        case .igneous: lava
        case .sedimentary: ocean
        case .metamorphic: grape
        }
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func roundedStyle(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// White rounded card with a soft shadow.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 24
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 24, fill: Color = Theme.card) -> some View {
        modifier(CardModifier(padding: padding, fill: fill))
    }
}

/// Chunky, bouncy button for kids.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.45), radius: configuration.isPressed ? 2 : 10, y: configuration.isPressed ? 1 : 6)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
