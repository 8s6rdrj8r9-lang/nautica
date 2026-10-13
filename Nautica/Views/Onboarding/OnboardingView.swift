import AppKit
import SwiftUI

/// Heuristic for Full Disk Access: `~/Library/Safari` is TCC-protected, so
/// enumerating it only succeeds once the user grants access (Prompt 15).
enum FullDiskAccess {
    static var isGranted: Bool {
        let probe = FileManager.default.homeURL
            .appendingPathComponent("Library/Safari").path
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// First-launch onboarding (Prompt 15). Deliberately plain: no animations,
/// one clear action per step, no surprise modals. Shown by `MainWindow`
/// until `hasCompletedOnboarding` is set.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step: OnboardingStep = .welcome
    @State private var hasFullDiskAccess = false
    /// Standard folders offered as initial favorites, all on by default.
    @State private var favorites: [(name: String, url: URL, selected: Bool)] = {
        let home = FileManager.default.homeURL
        return [
            ("Home", home, true),
            ("Desktop", home.appendingPathComponent("Desktop"), true),
            ("Documents", home.appendingPathComponent("Documents"), true),
            ("Downloads", home.appendingPathComponent("Downloads"), true),
            ("Pictures", home.appendingPathComponent("Pictures"), true),
        ]
    }()

    enum OnboardingStep {
        case welcome, permissions, favorites, complete
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch step {
            case .welcome: welcomeStep
            case .permissions: permissionsStep
            case .favorites: favoritesStep
            case .complete: completeStep
            }
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 460, minHeight: 380)
        // Poll for the permission grant while the permissions step is up;
        // when it flips, auto-advance.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            guard step == .permissions, !hasFullDiskAccess else { return }
            if FullDiskAccess.isGranted {
                hasFullDiskAccess = true
                step = .favorites
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Text("Welcome to Nautica")
                .font(.largeTitle)
            Text("Nautica is a local-first, privacy-respecting file manager inspired by Nemo.\nNo telemetry, local-first by default, fully open source.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue") { step = .permissions }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Text("Full Disk Access (macOS 27)")
                .font(.title)
            Text("To browse local folders, external volumes, and protected directories without sandboxing boundaries, macOS 27 requires Full Disk Access.\n\nNautica operates strictly on-device with zero telemetry, zero automated scraping, and no cloud egress by default.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open System Settings → Privacy & Security") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            Text("This step advances automatically as soon as access is granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Skip for Now") { step = .favorites }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var favoritesStep: some View {
        VStack(spacing: 16) {
            Text("Favorites")
                .font(.title)
            Text("These folders will appear in the sidebar. You can change them later.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                ForEach(favorites.indices, id: \.self) { index in
                    Toggle(favorites[index].name, isOn: $favorites[index].selected)
                }
            }
            Button("Continue") {
                SidebarModel.saveInitialFavorites(
                    favorites.filter(\.selected).map(\.url)
                )
                step = .complete
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Text("You're Ready")
                .font(.title)
            Text("Nautica is set up. Enjoy your files.")
                .foregroundStyle(.secondary)
            Button("Open Nautica") {
                hasCompletedOnboarding = true
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    OnboardingView()
}
