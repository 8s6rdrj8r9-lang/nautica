import AppKit
import Foundation

/// Manages floating standalone "Get Info" inspector windows (Finder ⌘I style).
/// Each inspected URL gets its own window controller so multiple items can be inspected
/// simultaneously without duplicating windows for the same item.
@MainActor
final class GetInfoService {
    static let shared = GetInfoService()

    private var openControllers: [URL: GetInfoWindowController] = [:]

    private init() {}

    /// Shows or brings to front the Get Info window for the specified URLs.
    func showInfo(for urls: [URL]) {
        guard !urls.isEmpty else { return }

        for url in urls {
            let standardized = url.standardizedFileURL
            if let existing = openControllers[standardized] {
                existing.showWindow(nil)
                existing.window?.makeKeyAndOrderFront(nil)
            } else {
                let controller = GetInfoWindowController(url: standardized)
                openControllers[standardized] = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)

                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: controller.window,
                    queue: .main
                ) { [weak self, weak controller] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        if let ctrl = controller {
                            self.openControllers.removeValue(forKey: ctrl.targetURL)
                        }
                    }
                }
            }
        }
    }

    /// Convenience for inspecting a single URL.
    func showInfo(for url: URL) {
        showInfo(for: [url])
    }
}
