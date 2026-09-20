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
            Constants.splitLayoutKey: SplitLayout.single.rawValue,
            Constants.defaultViewModeKey: ViewMode.list.rawValue,
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
        .defaultSize(width: 1060, height: 680)
        .modelContainer(for: FolderViewState.self)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { browserActions?.undo() }
                    .keyboardShortcut("z")
                Button("Redo") { browserActions?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") { browserActions?.copySelection() }
                    .keyboardShortcut("c")
                Button("Paste") { browserActions?.paste() }
                    .keyboardShortcut("v")
                Button("Move Here") { browserActions?.moveHere() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Button("Copy SHA-256 Checksum") { browserActions?.copySHA256Checksum() }
                Divider()
                Button("Rename…") { browserActions?.renameSelection() }
                Button("Batch Rename…") { browserActions?.batchRenameSelection() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Move to Trash") { browserActions?.trashSelection() }
                    .keyboardShortcut(KeyEquivalent(Character("\u{7F}")), modifiers: .command)
                Button("Put Back") { browserActions?.putBack() }
            }
            CommandGroup(after: .newItem) {
                Button("New Encrypted File Vault…") { browserActions?.openCreateVault() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Folder") { browserActions?.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Folder with Selection") { browserActions?.newFolderWithSelection() }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                Button("Duplicate") { browserActions?.duplicateSelection() }
                    .keyboardShortcut("d")
                Button("Make Alias") { browserActions?.makeAlias() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Show Original") { browserActions?.showOriginal() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Get Info") { browserActions?.getInfo() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Quick Look") { browserActions?.quickLook() }
                    .keyboardShortcut("y", modifiers: .command)
                Button("Edit Metadata…") { browserActions?.openMetadataEditor() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Menu("Tags") {
                    Button("Red") { browserActions?.toggleTag(.red) }
                        .keyboardShortcut("1", modifiers: .control)
                    Button("Orange") { browserActions?.toggleTag(.orange) }
                        .keyboardShortcut("2", modifiers: .control)
                    Button("Yellow") { browserActions?.toggleTag(.yellow) }
                        .keyboardShortcut("3", modifiers: .control)
                    Button("Green") { browserActions?.toggleTag(.green) }
                        .keyboardShortcut("4", modifiers: .control)
                    Button("Blue") { browserActions?.toggleTag(.blue) }
                        .keyboardShortcut("5", modifiers: .control)
                    Button("Purple") { browserActions?.toggleTag(.purple) }
                        .keyboardShortcut("6", modifiers: .control)
                    Button("Gray") { browserActions?.toggleTag(.gray) }
                        .keyboardShortcut("7", modifiers: .control)
                    Divider()
                    Button("Clear All Tags") { browserActions?.clearTags() }
                        .keyboardShortcut("0", modifiers: .control)
                }
                Divider()
                Button("Download from Cloud") { browserActions?.downloadCloudSelection() }
                Button("Remove Local Download") { browserActions?.evictCloudSelection() }
                Button("Find Duplicates in Folder…") { browserActions?.findDuplicatesInFolder() }
                Divider()
                Button("New Tab") {
                    // The new window picks this URL up in onAppear.
                    if let browserURL {
                        TabRestoreQueue.shared.enqueue(browserURL)
                    }
                    openWindow(id: "browser")
                }
                .keyboardShortcut("t")

                Button("Duplicate Tab") {
                    if let browserURL {
                        TabRestoreQueue.shared.enqueue(browserURL)
                    }
                    openWindow(id: "browser")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("Close Other Tabs") {
                    browserActions?.closeOtherTabs()
                }

                Button("Close Tabs to the Right") {
                    browserActions?.closeTabsToTheRight()
                }

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
                    .keyboardShortcut("1", modifiers: .command)
                Button("as List") { browserActions?.setViewMode(.list) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("as Columns") { browserActions?.setViewMode(.column) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("as Gallery") { browserActions?.setViewMode(.gallery) }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Menu("Use Groups") {
                    Button("None") { browserActions?.setGroupBy(.none) }
                        .keyboardShortcut("0", modifiers: [.command, .control])
                    Button("Kind") { browserActions?.setGroupBy(.kind) }
                        .keyboardShortcut("2", modifiers: [.command, .control])
                    Button("Date Modified") { browserActions?.setGroupBy(.dateModified) }
                        .keyboardShortcut("5", modifiers: [.command, .control])
                    Button("Date Created") { browserActions?.setGroupBy(.dateCreated) }
                        .keyboardShortcut("6", modifiers: [.command, .control])
                    Button("Size") { browserActions?.setGroupBy(.size) }
                        .keyboardShortcut("7", modifiers: [.command, .control])
                    Button("Tags") { browserActions?.setGroupBy(.tags) }
                        .keyboardShortcut("8", modifiers: [.command, .control])
                }
                Button("Show View Options") { browserActions?.showViewOptions() }
                    .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("Toggle Hidden Files") { browserActions?.toggleHiddenFiles() }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Divider()
                Menu("Panes") {
                    Button("Single Pane") { browserActions?.setSplitLayout(.single) }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("2 Columns (Horizontal)") { browserActions?.setSplitLayout(.horizontal2) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("2 Rows (Vertical)") { browserActions?.setSplitLayout(.vertical2) }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                    Button("4 Panes (Grid)") { browserActions?.setSplitLayout(.quad4) }
                        .keyboardShortcut("4", modifiers: [.command, .option])
                    Button("4 Columns (Horizontal)") { browserActions?.setSplitLayout(.horizontal4) }
                        .keyboardShortcut("5", modifiers: [.command, .option])
                    Button("4 Rows (Vertical)") { browserActions?.setSplitLayout(.vertical4) }
                        .keyboardShortcut("6", modifiers: [.command, .option])
                    Divider()
                    Button("Next Pane") { browserActions?.cycleNextPane() }
                        .keyboardShortcut(.tab, modifiers: .option)
                    Divider()
                    Button("Synchronized Navigation") { browserActions?.toggleSyncNavigation() }
                        .keyboardShortcut("s", modifiers: [.command, .option])
                    Button("Copy to Inactive Pane") { browserActions?.copyToInactivePane() }
                    Button("Move to Inactive Pane") { browserActions?.moveToInactivePane() }
                }
                Button("Toggle Sidebar") { browserActions?.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                Button("Toggle Dual Pane") { browserActions?.toggleDualPane() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Toggle Filter Bar") { browserActions?.toggleFilterBar() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Toggle Path Bar") { browserActions?.togglePathBar() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Toggle Inspector") { browserActions?.toggleInspector() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Menu("Inspector Panels") {
                    Button("Recent Folders") { browserActions?.showInspectorTab(.recents) }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                    Button("Directory Tree") { browserActions?.showInspectorTab(.tree) }
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    Button("File Info") { browserActions?.showInspectorTab(.info) }
                    Button("Drop Shelf") { browserActions?.showInspectorTab(.shelf) }
                    Button("Quick Actions") { browserActions?.showInspectorTab(.actions) }
                        .keyboardShortcut("a", modifiers: [.command, .option])
                    Button("Git Status") { browserActions?.showInspectorTab(.git) }
                        .keyboardShortcut("g", modifiers: [.command, .option])
                    Button("Media & Metadata") { browserActions?.showInspectorTab(.media) }
                        .keyboardShortcut("m", modifiers: [.command, .option])
                    Button("Terminal Console") { browserActions?.showInspectorTab(.terminal) }
                }
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
                Button("Network") {
                    browserActions?.navigateTo(URL(fileURLWithPath: "/Volumes"))
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Go to Folder…") { browserActions?.promptGoToFolder() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Connect to Server…") { browserActions?.promptConnectToServer() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Git") {
                Button("Commit Changes…") { browserActions?.gitCommit() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("View Diff…") { browserActions?.gitDiffSelection() }
                    .keyboardShortcut("d", modifiers: [.command, .control])
                Divider()
                Button("Stage Selection") { browserActions?.gitStageSelection() }
                Button("Unstage Selection") { browserActions?.gitUnstageSelection() }
                Button("Discard Selection…") { browserActions?.gitDiscardSelection() }
                Divider()
                Button("New Branch…") { browserActions?.gitCreateBranch() }
            }
            CommandGroup(after: .windowArrangement) {
                Button("Move Tab to New Window") {
                    browserActions?.moveTabToNewWindow()
                }
                Button("Merge All Windows") {
                    browserActions?.mergeAllWindows()
                }
                Divider()
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
