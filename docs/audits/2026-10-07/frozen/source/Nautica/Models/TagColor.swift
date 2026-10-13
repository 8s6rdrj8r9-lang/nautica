import AppKit
import Foundation
import SwiftUI

/// Standard macOS Finder color labels and their native color indices.
/// In macOS Finder:
/// 1 = Gray, 2 = Green, 3 = Purple, 4 = Blue, 5 = Yellow, 6 = Red, 7 = Orange.
public enum TagColor: Int, CaseIterable, Identifiable, Sendable, Codable {
    case red = 6
    case orange = 7
    case yellow = 5
    case green = 2
    case blue = 4
    case purple = 3
    case gray = 1

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }

    public var colorHex: String {
        switch self {
        case .red: return "#FF3B30"
        case .orange: return "#FF9500"
        case .yellow: return "#FFCC00"
        case .green: return "#34C759"
        case .blue: return "#007AFF"
        case .purple: return "#AF52DE"
        case .gray: return "#8E8E93"
        }
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }

    public var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }

    /// Finder shortcut key equivalent (e.g. ^1 for Red, ^2 for Orange, etc.)
    public var shortcutNumber: Int {
        switch self {
        case .red: return 1
        case .orange: return 2
        case .yellow: return 3
        case .green: return 4
        case .blue: return 5
        case .purple: return 6
        case .gray: return 7
        }
    }

    public static func from(shortcutNumber: Int) -> TagColor? {
        switch shortcutNumber {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        case 6: return .purple
        case 7: return .gray
        default: return nil
        }
    }

    public static func from(name: String) -> TagColor? {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray", "grey": return .gray
        default: return nil
        }
    }
}

/// Representation of a single parsed tag from macOS Finder or Nautica database.
public struct FileTagInfo: Hashable, Identifiable, Sendable {
    public var id: String { rawName }
    public let rawName: String
    public let displayName: String
    public let color: TagColor?

    public init(rawName: String) {
        self.rawName = rawName
        let parts = rawName.split(separator: "\n", maxSplits: 1)
        let name = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = name
        if parts.count > 1, let code = Int(parts[1]), let tagColor = TagColor(rawValue: code) {
            self.color = tagColor
        } else {
            self.color = TagColor.from(name: name)
        }
    }

    public init(name: String, color: TagColor?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color {
            self.rawName = "\(trimmed)\n\(color.rawValue)"
            self.displayName = trimmed
            self.color = color
        } else {
            self.rawName = trimmed
            self.displayName = trimmed
            self.color = TagColor.from(name: trimmed)
        }
    }
}
