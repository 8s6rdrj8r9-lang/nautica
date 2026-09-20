import AppKit
import SwiftUI

/// Window controller hosting the standalone "Get Info" inspector panel.
final class GetInfoWindowController: NSWindowController {
    let targetURL: URL

    init(url: URL) {
        self.targetURL = url

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(url.lastPathComponent) Info"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)

        let contentView = GetInfoView(targetURL: url) { [weak self] in
            self?.close()
        }
        window.contentView = NSHostingView(rootView: contentView)
        window.setFrameAutosaveName("GetInfo_\(url.lastPathComponent)")
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
