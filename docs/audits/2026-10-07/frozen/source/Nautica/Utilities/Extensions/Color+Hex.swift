import SwiftUI

extension Color {
    /// Parses "#RRGGBB" / "#RRGGBBAA" tag colors (Prompt 11); nil on bad input.
    init?(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        self.init(
            .sRGB,
            red: Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
            green: Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
            blue: Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
            opacity: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        self.init(
            srgbRed: CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0,
            green: CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0,
            blue: CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0,
            alpha: hasAlpha ? CGFloat(value & 0xFF) / 255.0 : 1.0
        )
    }
}
