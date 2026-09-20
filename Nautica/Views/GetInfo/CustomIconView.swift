import AppKit
import SwiftUI

/// Interactive icon view inside the "Get Info" inspector (⌘I).
/// Supports clicking to focus, Cmd+C to copy icon, Cmd+V to paste custom icon,
/// Backspace/Delete to reset to default icon, and dragging and dropping images directly.
struct CustomIconView: NSViewRepresentable {
    let url: URL
    var onIconChanged: (() -> Void)?

    func makeNSView(context: Context) -> CustomIconBoxView {
        let view = CustomIconBoxView(url: url)
        view.onIconChanged = onIconChanged
        return view
    }

    func updateNSView(_ nsView: CustomIconBoxView, context: Context) {
        nsView.url = url
        nsView.onIconChanged = onIconChanged
        nsView.needsDisplay = true
    }
}

final class CustomIconBoxView: NSView {
    var url: URL
    var onIconChanged: (() -> Void)?

    private var isFocused: Bool {
        window?.firstResponder == self
    }

    init(url: URL) {
        self.url = url
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        wantsLayer = true
        registerForDraggedTypes([
            .fileURL,
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.image")
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let iconRect = bounds.insetBy(dx: 4, dy: 4)
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        if isFocused {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func keyDown(with event: NSEvent) {
        let hasCommand = event.modifierFlags.contains(.command)

        if hasCommand, let char = event.charactersIgnoringModifiers?.lowercased() {
            if char == "c" {
                // Copy icon image to pasteboard
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([icon])
                NSSound.beep()
                return
            } else if char == "v" {
                // Paste icon from pasteboard
                if pasteIconFromPasteboard() {
                    return
                }
            }
        }

        // Delete / Backspace: Revert to default system icon
        let isDelete = event.keyCode == 51 || event.keyCode == 117 // Backspace or Forward Delete
        if isDelete {
            _ = NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
            needsDisplay = true
            onIconChanged?()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Pasteboard & Drag-Drop Handling

    private func pasteIconFromPasteboard() -> Bool {
        let pb = NSPasteboard.general

        // 1. Try reading NSImage directly
        if let image = NSImage(pasteboard: pb) {
            return applyCustomIcon(image)
        }

        // 2. Try reading file URL
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstURL = urls.first {
            if let image = NSImage(contentsOf: firstURL) ?? Optional(NSWorkspace.shared.icon(forFile: firstURL.path)) {
                return applyCustomIcon(image)
            }
        }

        return false
    }

    private func applyCustomIcon(_ image: NSImage) -> Bool {
        // Ensure image has a representation and suitable dimensions
        let targetSize = NSSize(width: 512, height: 512)
        let resized = NSImage(size: targetSize, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }

        let success = NSWorkspace.shared.setIcon(resized, forFile: url.path, options: [])
        if success {
            needsDisplay = true
            onIconChanged?()
        }
        return success
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ||
           pb.canReadObject(forClasses: [NSImage.self], options: nil) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let image = NSImage(pasteboard: pb) {
            return applyCustomIcon(image)
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstURL = urls.first {
            if let img = NSImage(contentsOf: firstURL) ?? Optional(NSWorkspace.shared.icon(forFile: firstURL.path)) {
                return applyCustomIcon(img)
            }
        }
        return false
    }
}
