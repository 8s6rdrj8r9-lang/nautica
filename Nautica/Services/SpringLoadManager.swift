import Foundation
import AppKit

/// Coordinates spring-loaded folder behavior across Nautica file views.
/// When dragging over a folder, hovering for 0.7 seconds (or pressing Spacebar)
/// triggers an automatic spring action (expanding inline in list view,
/// drilling in in icon/sidebar views, or opening the next column in column view).
@MainActor
final class SpringLoadManager {
    static let shared = SpringLoadManager()

    /// Default hover duration before springing open.
    static let defaultHoverDelay: TimeInterval = 0.7

    private var hoverTimer: Timer?
    private(set) var activeTargetURL: URL?
    private var activeAction: ((URL) -> Void)?

    private init() {}

    /// Registers a hover event over a potential spring-load folder.
    /// If the hover remains on this URL for `delay` seconds, `action` fires.
    func hover(on url: URL, delay: TimeInterval = defaultHoverDelay, action: @escaping (URL) -> Void) {
        if activeTargetURL == url {
            // Already hovering and counting down on this URL
            return
        }

        cancel()
        self.activeTargetURL = url
        self.activeAction = action

        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.activeTargetURL == url else { return }
            let target = url
            let block = self.activeAction
            self.cancel()
            block?(target)
        }
    }

    /// Triggers immediate spring loading (e.g. when user taps Spacebar during a drag).
    func triggerImmediate() {
        guard let url = activeTargetURL, let block = activeAction else { return }
        cancel()
        block(url)
    }

    /// Cancels any in-flight hover timer when drag moves away or ends.
    func cancel() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        activeTargetURL = nil
        activeAction = nil
    }
}
