import AppKit
import Foundation

/// Supported terminal emulators for "Open in Terminal" (Prompt 13).
enum TerminalEmulator: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iTerm = "iTerm"
    case kitty = "Kitty"
    case warp = "Warp"

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .kitty: return "net.kovidgoyal.kitty"
        case .warp: return "dev.warp.Warp-Stable"
        }
    }

    /// Bundle URL when the emulator is installed, else nil.
    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// Opens directories in the user's preferred terminal emulator (Prompt 13).
actor TerminalService {
    static let shared = TerminalService()

    enum TerminalError: Error {
        case emulatorNotInstalled(TerminalEmulator)
        case appleScriptFailed(String)
    }

    /// Installed emulators, in declaration order (Terminal.app always first).
    nonisolated func detectInstalledTerminals() -> [TerminalEmulator] {
        TerminalEmulator.allCases.filter { $0.appURL != nil }
    }

    /// The configured emulator, falling back to Terminal.app when the choice
    /// is unset or no longer installed.
    nonisolated func defaultTerminal() -> TerminalEmulator {
        if let raw = UserDefaults.standard.string(forKey: Constants.defaultTerminalKey),
           let emulator = TerminalEmulator(rawValue: raw),
           emulator.appURL != nil {
            return emulator
        }
        return .terminal
    }

    /// Opens a new terminal window with the working directory set to `url`.
    /// Falls back to Terminal.app if the requested emulator is missing.
    func openTerminal(at url: URL, emulator: TerminalEmulator) async throws {
        let emulator = emulator.appURL != nil ? emulator : .terminal
        switch emulator {
        case .terminal:
            try openTerminalApp(at: url)
        case .iTerm, .warp:
            // Both accept a folder URL and start a session in it.
            guard let appURL = emulator.appURL else {
                throw TerminalError.emulatorNotInstalled(emulator)
            }
            try await openFolder(url, withApplicationAt: appURL)
        case .kitty:
            guard let appURL = emulator.appURL else {
                throw TerminalError.emulatorNotInstalled(emulator)
            }
            let process = Process()
            process.executableURL = appURL.appendingPathComponent("Contents/MacOS/kitty")
            process.arguments = ["--directory", url.path]
            try process.run()
        }
    }

    // MARK: - Private

    /// Terminal.app: AppleScript `do script "cd …"` in a new window.
    private func openTerminalApp(at url: URL) throws {
        // Escape for the AppleScript string literal; `quoted form of` then
        // makes it safe for the shell.
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            do script "cd " & quoted form of "\(escaped)"
            activate
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw TerminalError.appleScriptFailed(error.description)
        }
    }

    private func openFolder(_ url: URL, withApplicationAt appURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [url], withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
