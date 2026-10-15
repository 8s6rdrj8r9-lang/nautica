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
            RightDockSettingsView()
                .tabItem { Label("Pinned Navigation", systemImage: "pin") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            TerminalSettingsTab()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            VaultSecuritySettingsTab()
                .tabItem { Label("Security & Vaults", systemImage: "lock.shield") }
            IntelligenceSettingsTab()
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 600, idealHeight: 700)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(Constants.defaultNewWindowFolderKey) private var newWindowFolder = "home"
    @AppStorage(Constants.showExtensionsKey) private var showExtensions = true
    @AppStorage(Constants.confirmTrashKey) private var confirmTrash = true
    @AppStorage(Constants.showHiddenFilesKey) private var showHiddenFiles = false
    @State private var isDefaultFileManager = DefaultFileManagerService.shared.isDefaultFileManager()

    var body: some View {
        Form {
            Section("General Behavior") {
                Picker("New windows open:", selection: $newWindowFolder) {
                    Text("Home").tag("home")
                    Text("Desktop").tag("desktop")
                    Text("Last visited").tag("lastVisited")
                }
                Toggle("Show file extensions", isOn: $showExtensions)
                Toggle("Confirm before moving to Trash", isOn: $confirmTrash)
                Toggle("Show hidden files by default", isOn: $showHiddenFiles)
            }

            Section("System Integration") {
                Toggle("Set Nautica as Default File Manager", isOn: Binding(
                    get: { isDefaultFileManager },
                    set: { newValue in
                        if newValue {
                            _ = DefaultFileManagerService.shared.setAsDefault()
                        } else {
                            _ = DefaultFileManagerService.shared.restoreFinder()
                        }
                        isDefaultFileManager = DefaultFileManagerService.shared.isDefaultFileManager()
                    }
                ))
                Text("Uses macOS LaunchServices to route folder opens to Nautica without disabling or modifying System Integrity Protection (SIP). Reversible anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            isDefaultFileManager = DefaultFileManagerService.shared.isDefaultFileManager()
        }
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
            Section("Files Sidebar") {
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
                    Text("Columns").tag(ViewMode.column.rawValue)
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
            Text("These sizing controls apply to the Files workspace. Saved per-folder view settings override the default view. The toolbar icon slider uses the same icon-size setting.")
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
    @State private var confirmReset = false
    @State private var resetError: String?

    var body: some View {
        Form {
            Button("Reset All View States…") {
                didResetViewStates = false
                confirmReset = true
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
        .confirmationDialog("Reset all per-folder view settings?", isPresented: $confirmReset) {
            Button("Reset View Settings", role: .destructive) { resetViewStates() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes saved folder layouts and sorting preferences. Your files, tags, Objects and Views are preserved. This cannot be undone.")
        }
        .alert("Could Not Reset View Settings", isPresented: Binding(get: { resetError != nil }, set: { if !$0 { resetError = nil } })) {
            Button("OK") { resetError = nil }
        } message: { Text(resetError ?? "") }
    }

    private func resetViewStates() {
        do {
            try modelContext.delete(model: FolderViewState.self)
            try modelContext.save()
            didResetViewStates = true
        } catch {
            modelContext.rollback()
            didResetViewStates = false
            resetError = error.localizedDescription
        }
    }

    private func reveal(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Intelligence & AI (macOS 27)

private struct IntelligenceSettingsTab: View {
    @AppStorage(Constants.aiEnabledKey) private var aiEnabled = false
    @AppStorage(Constants.aiProviderKey) private var aiProvider = AIService.Provider.appleFoundation.rawValue
    @AppStorage(Constants.enableAIBackupKey) private var enableAIBackup = false
    @AppStorage(AICloudPolicy.consentKey) private var cloudConsent = ""
    @AppStorage(AICloudPolicy.localOnlyKey) private var localOnly = true
    @State private var replacementKey = ""
    @State private var hasKey = false
    @State private var keyError: String?
    @State private var showCloudDisclosure = false

    private var cloudAuthorized: Bool { cloudConsent == AICloudPolicy.version && !localOnly }

    var body: some View {
        Form {
            Section("On-Device Intelligence") {
                Toggle("Enable Intelligence Features", isOn: $aiEnabled)
                Text("Directory summaries, suggested tags and file explanations run on this Mac by default. Core file browsing works with Intelligence disabled.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep AI Requests on This Mac", isOn: $localOnly)
                    .onChange(of: localOnly) { _, value in
                        if value {
                            enableAIBackup = false
                            aiProvider = AIService.Provider.appleFoundation.rawValue
                        }
                    }
                Text("Local-only mode blocks every cloud AI request, including fallback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if aiEnabled {
                Section("Processing") {
                    Picker("Primary Engine", selection: $aiProvider) {
                        Text("On-Device").tag(AIService.Provider.appleFoundation.rawValue)
                        if cloudAuthorized { Text("OpenAI (Cloud)").tag(AIService.Provider.openAI.rawValue) }
                    }
                    if !cloudAuthorized {
                        Text("Cloud requests are blocked until you review and allow OpenAI processing.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Review Cloud Processing…") { showCloudDisclosure = true }
                    } else {
                        Toggle("Use OpenAI When On-Device AI Is Unavailable", isOn: $enableAIBackup)
                        Text("Cloud requests send the selected task's filenames, folder summary or up to 4,000 bytes of text to OpenAI using your API account. API charges may apply.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Revoke Cloud Processing") {
                            cloudConsent = ""
                            localOnly = true
                            enableAIBackup = false
                            aiProvider = AIService.Provider.appleFoundation.rawValue
                        }
                    }
                }
            }
            Section("OpenAI Credential") {
                    Text(hasKey ? "An API key is stored in macOS Keychain." : "No API key is stored.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("New or Replacement API Key", text: $replacementKey)
                    HStack {
                        Button("Save Key") {
                            do {
                                try AIAPIKeyStore.save(replacementKey)
                                replacementKey = ""
                                hasKey = true
                            } catch { keyError = error.localizedDescription }
                        }.disabled(replacementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove Key", role: .destructive) {
                            do {
                                try AIAPIKeyStore.remove()
                                replacementKey = ""
                                hasKey = false
                            } catch { keyError = error.localizedDescription }
                        }.disabled(!hasKey)
                    }
                    Text("Keys are stored securely on this Mac. Saving a key does not enable cloud processing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            do { hasKey = try AIAPIKeyStore.loadMigratingLegacyKey() != nil }
            catch { keyError = error.localizedDescription }
            if !cloudAuthorized { aiProvider = AIService.Provider.appleFoundation.rawValue }
        }
        .confirmationDialog("Allow Cloud AI Processing?", isPresented: $showCloudDisclosure) {
            Button("Allow OpenAI Processing") {
                enableAIBackup = false
                cloudConsent = AICloudPolicy.version
                localOnly = false
            }
            Button("Keep Requests Local", role: .cancel) { }
        } message: {
            Text("For AI tasks you request, OpenAI may receive filenames and folder information, or up to 4,000 bytes from the selected text file. Requests use your API account and may incur charges. Only send information you are authorized to share. You can revoke future requests or enable local-only mode here. Already sent information cannot be recalled. Automatic fallback remains off until you enable it.")
        }
        .alert("API Key Could Not Be Updated", isPresented: Binding(get: { keyError != nil }, set: { if !$0 { keyError = nil } })) {
            Button("OK") { keyError = nil }
        } message: { Text(keyError ?? "") }
    }
}

#Preview {
    SettingsView()
}

