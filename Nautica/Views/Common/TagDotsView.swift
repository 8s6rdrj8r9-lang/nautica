import AppKit
import SwiftUI

/// Renders native Finder-style overlapping color tag dots.
public struct TagDotsView: View {
    public let colors: [TagColor]
    public var dotSize: CGFloat = 8
    public var maxDots: Int = 3

    public init(colors: [TagColor], dotSize: CGFloat = 8, maxDots: Int = 3) {
        self.colors = colors
        self.dotSize = dotSize
        self.maxDots = maxDots
    }

    public var body: some View {
        let visibleColors = Array(colors.prefix(maxDots))
        if !visibleColors.isEmpty {
            HStack(spacing: -dotSize * 0.3) {
                ForEach(Array(visibleColors.enumerated()), id: \.offset) { index, color in
                    Circle()
                        .fill(color.color)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1)
                        )
                        .zIndex(Double(visibleColors.count - index))
                }
            }
        }
    }
}

/// AppKit rendering utility for composite tag dots in NSTableView and NSCollectionView cells.
@MainActor
public enum TagDotsHelper {
    private static var imageCache: [String: NSImage] = [:]

    /// Generates or retrieves a cached composite image representing the given color dots.
    public static func image(for colors: [TagColor], diameter: CGFloat = 8, maxDots: Int = 3) -> NSImage? {
        let visible = Array(colors.prefix(maxDots))
        guard !visible.isEmpty else { return nil }

        let key = "\(visible.map { String($0.rawValue) }.joined(separator: ","))_\(diameter)"
        if let cached = imageCache[key] {
            return cached
        }

        let overlap: CGFloat = diameter * 0.3
        let width = diameter + CGFloat(visible.count - 1) * (diameter - overlap)
        let height = diameter
        let size = NSSize(width: ceil(width), height: ceil(height))

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            for (index, color) in visible.enumerated() {
                let x = CGFloat(index) * (diameter - overlap)
                let dotRect = CGRect(x: x, y: 0, width: diameter, height: diameter)

                // Fill color dot
                context.setFillColor(color.nsColor.cgColor)
                context.fillEllipse(in: dotRect)

                // Outline border for overlapping separation
                context.setStrokeColor(NSColor.windowBackgroundColor.cgColor)
                context.setLineWidth(1.0)
                context.strokeEllipse(in: dotRect.insetBy(dx: 0.5, dy: 0.5))
            }
            return true
        }

        imageCache[key] = image
        return image
    }
}
