import SwiftData
import SwiftUI

/// Preferences window (Prompt 14). All settings live in `UserDefaults` via
/// `@AppStorage` and apply immediately. Presented by the `Settings` scene in
/// `NauticaApp` (Cmd+,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            TerminalSettingsTab()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(Constants.defaultNewWindowFolderKey) private var newWindowFolder = "home"
    @AppStorage(Constants.showExtensionsKey) private var showExtensions = true
    @AppStorage(Constants.confirmTrashKey) private var confirmTrash = true
    @AppStorage(Constants.showHiddenFilesKey) private var showHiddenFiles = false

    var body: some View {
        Form {
            Picker("New windows open:", selection: $newWindowFolder) {
                Text("Home").tag("home")
                Text("Desktop").tag("desktop")
                Text("Last visited").tag("lastVisited")
            }
            Toggle("Show file extensions", isOn: $showExtensions)
            Toggle("Confirm before moving to Trash", isOn: $confirmTrash)
            Toggle("Show hidden files by default", isOn: $showHiddenFiles)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @AppStorage(Constants.defaultViewModeKey) private var defaultViewMode = ViewMode.icon.rawValue
    @AppStorage(Constants.defaultIconSizeKey) private var defaultIconSize: Double = 64
    @AppStorage(Constants.sidebarWidthKey) private var sidebarWidth: Double = 220
    @AppStorage(Constants.useSystemAccentKey) private var useSystemAccent = true

    var body: some View {
        Form {
            Picker("Default view mode:", selection: $defaultViewMode) {
                Text("Icons").tag(ViewMode.icon.rawValue)
                Text("List").tag(ViewMode.list.rawValue)
            }
            .pickerStyle(.segmented)

            Slider(value: $defaultIconSize, in: 32...256, step: 4) {
                Text("Default icon size: \(Int(defaultIconSize)) px")
            }
            Slider(value: $sidebarWidth, in: 160...360, step: 4) {
                Text("Sidebar width: \(Int(sidebarWidth)) px")
            }
            Toggle("Use system accent color", isOn: $useSystemAccent)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Terminal

private struct TerminalSettingsTab: View {
    @AppStorage(Constants.defaultTerminalKey) private var defaultTerminal = TerminalEmulator.terminal.rawValue
    @AppStorage(Constants.terminalShellKey) private var terminalShell = ""

    /// Only emulators actually installed on this Mac.
    private var installed: [TerminalEmulator] {
        TerminalService.shared.detectInstalledTerminals()
    }

    var body: some View {
        Form {
            Picker("Default terminal:", selection: $defaultTerminal) {
                ForEach(installed) { emulator in
                    Text(emulator.rawValue).tag(emulator.rawValue)
                }
            }
            TextField("Custom shell path (empty = login shell)", text: $terminalShell)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.checkForUpdatesKey) private var checkForUpdates = false
    @State private var didResetViewStates = false

    var body: some View {
        Form {
            Button("Reset All View States…") {
                resetViewStates()
            }
            if didResetViewStates {
                Text("Per-folder view settings were reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Reveal Tags Database in Finder") {
                reveal(Constants.appSupportURL.appendingPathComponent("Tags.sqlite"))
            }
            Button("Reveal View State Store in Finder") {
                reveal(
                    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                        .first!.appendingPathComponent("default.store")
                )
            }
            Toggle("Check for updates (disabled until v1.1)", isOn: $checkForUpdates)
                .disabled(true)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func resetViewStates() {
        try? modelContext.delete(model: FolderViewState.self)
        try? modelContext.save()
        didResetViewStates = true
    }

    private func reveal(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#Preview {
    SettingsView()
}
