import Foundation

/// Back/forward navigation stacks for the browser window.
@Observable
final class NavigationHistory {
    var backStack: [URL] = []
    var forwardStack: [URL] = []
    var currentURL: URL

    init(currentURL: URL) {
        self.currentURL = currentURL
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Pushes the current location onto the back stack, clears the forward
    /// stack, and makes `url` current.
    func navigate(to url: URL) {
        guard url != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
    }

    /// Pops the back stack, moving the current location onto the forward stack.
    func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(currentURL)
        currentURL = previous
        return previous
    }

    /// Pops the forward stack, moving the current location onto the back stack.
    func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(currentURL)
        currentURL = next
        return next
    }
}
