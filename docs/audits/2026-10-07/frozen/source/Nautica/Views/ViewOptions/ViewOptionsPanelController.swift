import AppKit
import SwiftUI

/// Window controller hosting the floating View Options HUD panel (⌘J).
final class ViewOptionsPanelController: NSWindowController, NSWindowDelegate {

    init(rootView: AnyView) {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 280, height: 420),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.title = "View Options"
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: rootView)

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updateRootView(_ rootView: AnyView) {
        if let hosting = window?.contentViewController as? NSHostingController<AnyView> {
            hosting.rootView = rootView
        } else {
            window?.contentViewController = NSHostingController(rootView: rootView)
        }
    }

    func windowWillClose(_ notification: Notification) {
        ViewOptionsService.shared.panelDidClose()
    }
}
