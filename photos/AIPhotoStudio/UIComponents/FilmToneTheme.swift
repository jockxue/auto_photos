import SwiftUI

enum FilmToneTheme {
    static let background = rgb(0x12, 0x12, 0x12)
    static let primaryText = rgb(0xF5, 0xF5, 0xF7)
    static let secondaryText = rgb(0x8E, 0x8E, 0x93)
    static let accent = rgb(0xE2, 0xB5, 0x6A)
    static let accentText = rgb(0x2A, 0x21, 0x16)
    static let chipBackground = rgb(0x2A, 0x2A, 0x2C)
    static let sliderTrack = rgb(0x3A, 0x3A, 0x3C)
    static let sliderThumb = rgb(0xFF, 0xFF, 0xFF)
    static let cardBackground = rgb(0x1C, 0x1C, 0x1E)
    static let tabBar = rgb(0x0C, 0x0C, 0x0C)
    static let tabInactive = rgb(0x6A, 0x6A, 0x6E)
    static let divider = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 20.0 / 255)

    static let largeTitle = Font.system(size: 28, weight: .semibold)
    static let pageTitle = Font.system(size: 17, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let button = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)

    static let cardRadius: CGFloat = 16
    static let chipRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 22

    private static func rgb(_ red: UInt32, _ green: UInt32, _ blue: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}
