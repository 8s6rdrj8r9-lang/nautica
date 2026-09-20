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
            VaultSecuritySettingsTab()
                .tabItem { Label("Security & Vaults", systemImage: "lock.shield") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 650)
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
    @AppStorage(Constants.defaultIconSizeKey) private var iconSize: Double = 64
    @AppStorage(Constants.sidebarWidthKey) private var sidebarWidth: Double = 220
    @AppStorage(Constants.sidebarAutoWidthKey) private var sidebarAutoWidth = false
    @AppStorage(Constants.sidebarFontSizeKey) private var sidebarFontSize: Double = 13
    @AppStorage(Constants.sidebarSpacingKey) private var sidebarSpacing: Double = 4
    @AppStorage(Constants.listFontSizeKey) private var listFontSize: Double = 13
    @AppStorage(Constants.listIconSizeKey) private var listIconSize: Double = 16
    @AppStorage(Constants.listSpacingKey) private var listSpacing: Double = 2
    @AppStorage(Constants.iconFontSizeKey) private var iconFontSize: Double = 11
    @AppStorage(Constants.iconSpacingKey) private var iconSpacing: Double = 10
    @AppStorage(Constants.useSystemAccentKey) private var useSystemAccent = true

    var body: some View {
        Form {
            Section("Sidebar") {
                SizeSetting("Font size", value: $sidebarFontSize, range: 10...24)
                SizeSetting("Row spacing", value: $sidebarSpacing, range: 0...16)
                SizeSetting("Width", value: $sidebarWidth, range: 160...600, step: 10)
                    .disabled(sidebarAutoWidth)
                Toggle("Auto width", isOn: $sidebarAutoWidth)
                Text("Fits the longest sidebar item, up to 600 pt to leave room for files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Main window") {
                Picker("Default view:", selection: $defaultViewMode) {
                    Text("Icons").tag(ViewMode.icon.rawValue)
                    Text("List").tag(ViewMode.list.rawValue)
                }
                .pickerStyle(.segmented)
                Toggle("Use system accent color", isOn: $useSystemAccent)
            }
            Section("List view") {
                SizeSetting("Font size", value: $listFontSize, range: 10...24)
                SizeSetting("Icon size", value: $listIconSize, range: 12...64, step: 2)
                SizeSetting("Row spacing", value: $listSpacing, range: 0...20)
            }
            Section("Icon view") {
                SizeSetting("Font size", value: $iconFontSize, range: 10...24)
                SizeSetting("Icon size", value: $iconSize, range: 32...256, step: 4)
                SizeSetting("Grid spacing", value: $iconSpacing, range: 0...40, step: 2)
            }
            Text("Sizing changes apply immediately to all windows. The toolbar icon slider uses the same setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct SizeSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) points")
            Text("\(Int(value)) pt")
                .monospacedDigit()
                .frame(width: 55, alignment: .trailing)
        }
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

// MARK: - Security & Vaults

private struct MountedVaultItem: Identifiable {
    var id: URL { url }
    let url: URL
    let mountPoint: URL
}

private struct VaultSecuritySettingsTab: View {
    @AppStorage(Constants.vaultAutoLockOnSleepKey) private var autoLockOnSleep = true
    @AppStorage(Constants.vaultAutoLockOnScreenLockKey) private var autoLockOnScreenLock = true
    @AppStorage(Constants.vaultInactivityTimeoutKey) private var inactivityTimeout = 15
    @ObservedObject private var automation = VaultAutomationService.shared
    @State private var isLockingAll = false

    private var mountedVaults: [MountedVaultItem] {
        automation.activeVaults.map { MountedVaultItem(url: $0.url, mountPoint: $0.mountPoint) }
    }

    var body: some View {
        Form {
            Section("Vault Auto-Lock Behavior") {
                Toggle("Auto-lock vaults when Mac goes to sleep", isOn: $autoLockOnSleep)
                Toggle("Auto-lock vaults when screen is locked", isOn: $autoLockOnScreenLock)
                Picker("Auto-lock when inactive for:", selection: $inactivityTimeout) {
                    Text("Never").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
            }

            Section("Mounted Vaults (\(mountedVaults.count))") {
                if mountedVaults.isEmpty {
                    Text("No file vaults are currently mounted.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    List {
                        ForEach(mountedVaults) { vault in
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(vault.url.lastPathComponent)
                                        .font(.body.weight(.medium))
                                    Text(vault.mountPoint.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Lock") {
                                    Task {
                                        _ = try? await VaultService.shared.lockVault(at: vault.url)
                                        VaultAutomationService.shared.refreshActiveVaults()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 200)

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            isLockingAll = true
                            Task {
                                _ = await VaultService.shared.lockAllVaults()
                                VaultAutomationService.shared.refreshActiveVaults()
                                isLockingAll = false
                            }
                        } label: {
                            if isLockingAll {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Lock All Vaults", systemImage: "lock.slash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLockingAll)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            automation.refreshActiveVaults()
        }
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
