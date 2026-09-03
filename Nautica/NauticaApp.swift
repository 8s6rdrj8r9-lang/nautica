import AppKit
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Queue the previous session's tabs; each new browser window pops one
    /// URL as it appears, and the windows merge into native tabs.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults so settings read true before first change.
        UserDefaults.standard.register(defaults: [
            Constants.showExtensionsKey: true,
            Constants.confirmTrashKey: true,
            Constants.useSystemAccentKey: true,
        ])
        TabRestoreQueue.shared.enqueue(contentsOf: WindowTabRegistry.shared.restoredURLs())
        // Create the tag database on first launch (Prompt 11).
        Task { try? await TagService.shared.setupDatabase() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowTabRegistry.shared.save()
    }
}

@main
struct NauticaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    /// Current directory of the key browser window, if one is focused.
    @FocusedValue(\.browserURL) private var browserURL
    /// File operations of the key browser window, if one is focused.
    @FocusedValue(\.browserActions) private var browserActions

    var body: some Scene {
        WindowGroup(id: "browser") {
            MainWindow()
        }
        .modelContainer(for: FolderViewState.self)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") { browserActions?.copySelection() }
                    .keyboardShortcut("c")
                Button("Paste") { browserActions?.paste() }
                    .keyboardShortcut("v")
                Button("Move Here") { browserActions?.moveHere() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Divider()
                Button("Rename…") { browserActions?.renameSelection() }
                Button("Move to Trash") { browserActions?.trashSelection() }
                    .keyboardShortcut(KeyEquivalent(Character("\u{7F}")), modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    // The new window picks this URL up in onAppear.
                    if let browserURL {
                        TabRestoreQueue.shared.enqueue(browserURL)
                    }
                    openWindow(id: "browser")
                }
                .keyboardShortcut("t")

                Button("Open in Terminal") {
                    if let browserURL {
                        Task {
                            try? await TerminalService.shared.openTerminal(
                                at: browserURL,
                                emulator: TerminalService.shared.defaultTerminal()
                            )
                        }
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("as Icons") { browserActions?.setViewMode(.icon) }
                    .keyboardShortcut("1", modifiers: [.command, .control])
                Button("as List") { browserActions?.setViewMode(.list) }
                    .keyboardShortcut("2", modifiers: [.command, .control])
                Divider()
                Button("Toggle Hidden Files") { browserActions?.toggleHiddenFiles() }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Divider()
                Button("Tree Panel") { browserActions?.toggleTreePanel() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
            CommandMenu("Go") {
                Button("Back") { browserActions?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { browserActions?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Enclosing Folder") { browserActions?.goToEnclosingFolder() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button("Home") {
                    browserActions?.navigateTo(FileManager.default.homeURL)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Desktop") {
                    browserActions?.navigateTo(
                        FileManager.default.homeURL.appendingPathComponent("Desktop")
                    )
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Documents") {
                    browserActions?.navigateTo(
                        FileManager.default.homeURL.appendingPathComponent("Documents")
                    )
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Downloads") {
                    browserActions?.navigateTo(
                        FileManager.default.homeURL.appendingPathComponent("Downloads")
                    )
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Go to Folder…") { browserActions?.promptGoToFolder() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                Button("Show Next Tab") {
                    NSApp.keyWindow?.selectNextTab(nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Show Previous Tab") {
                    NSApp.keyWindow?.selectPreviousTab(nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Show Tab \(index)") {
                        selectTab(index - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }
        }

        // Prompt 14: native preferences window (Cmd+,).
        Settings {
            SettingsView()
        }
        .modelContainer(for: FolderViewState.self)
    }

    private func selectTab(_ index: Int) {
        guard let window = NSApp.keyWindow,
              let tabs = window.tabbedWindows,
              tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }
}
