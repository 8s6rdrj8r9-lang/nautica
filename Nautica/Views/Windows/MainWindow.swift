import SwiftUI

/// Root window content. Shows onboarding on first launch (Prompt 15), then
/// the browser. Each window carries one `BrowserView`; windows merge into
/// native macOS tabs (Prompt 8).
struct MainWindow: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            BrowserView()
        } else {
            OnboardingView()
        }
    }
}
