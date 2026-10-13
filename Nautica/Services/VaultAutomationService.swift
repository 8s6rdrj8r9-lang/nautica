import Foundation
import AppKit
import Combine

/// Service that automates the lifecycle of encrypted APFS File Vaults:
/// - Auto-locks active vaults on system sleep or display sleep
/// - Auto-locks active vaults when the screen is locked
/// - Automatically detaches vaults after a configurable duration of user inactivity
@MainActor
public final class VaultAutomationService: ObservableObject {
    public static let shared = VaultAutomationService()

    @Published public private(set) var activeVaults: [(url: URL, mountPoint: URL)] = []
    @Published public private(set) var lastActivityDate: Date = Date()
    @Published public private(set) var isMonitoring: Bool = false

    private var eventMonitor: Any?
    private var inactivityTimer: Timer?
    private var sleepObserver: Any?
    private var screensSleepObserver: Any?
    private var screenLockObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Starts system notification observers and the idle inactivity timer.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastActivityDate = Date()

        // 1. System Sleep Notification
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let shouldLock = UserDefaults.standard.object(forKey: Constants.vaultAutoLockOnSleepKey) as? Bool ?? true
            if shouldLock {
                Task { await self.lockAllVaultsNow() }
            }
        }

        // 2. Displays / Screens Sleep Notification
        screensSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let shouldLock = UserDefaults.standard.object(forKey: Constants.vaultAutoLockOnScreenLockKey) as? Bool ?? true
            if shouldLock {
                Task { await self.lockAllVaultsNow() }
            }
        }

        // 3. Screen Locked Notification (Distributed Notification)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        // 4. Local User Activity Monitor (mouse movement, key presses, clicks)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel
        ]) { [weak self] event in
            self?.recordActivity()
            return event
        }

        // 5. Inactivity Heartbeat Timer (runs every 15 seconds)
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInactivityTimeout()
                self?.refreshActiveVaults()
            }
        }

        refreshActiveVaults()
    }

    /// Stops all observers and timers.
    public func stopMonitoring() {
        isMonitoring = false

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let screensSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screensSleepObserver)
            self.screensSleepObserver = nil
        }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    /// Records that the user was active right now.
    public func recordActivity() {
        lastActivityDate = Date()
    }

    /// Queries the system for all mounted encrypted vaults managed by Nautica.
    public func refreshActiveVaults() {
        activeVaults = VaultService.shared.mountedVaults(onlyManaged: true)
    }

    /// Immediately detaches and locks all mounted managed vaults.
    @discardableResult
    public func lockAllVaultsNow() async -> [URL: Error] {
        let failures = await VaultService.shared.lockAllVaults(force: false)
        refreshActiveVaults()
        return failures
    }

    @objc private func handleScreenLocked() {
        let shouldLock = UserDefaults.standard.object(forKey: Constants.vaultAutoLockOnScreenLockKey) as? Bool ?? true
        if shouldLock {
            Task { @MainActor in
                await self.lockAllVaultsNow()
            }
        }
    }

    private func checkInactivityTimeout() {
        let timeoutMinutes = UserDefaults.standard.object(forKey: Constants.vaultInactivityTimeoutKey) as? Int ?? 15
        guard timeoutMinutes > 0 else { return } // 0 = disabled

        let idleSeconds = Date().timeIntervalSince(lastActivityDate)
        let maxIdleSeconds = Double(timeoutMinutes * 60)

        if idleSeconds >= maxIdleSeconds {
            // Check if any managed vaults are mounted before locking
            let mounted = VaultService.shared.mountedVaults(onlyManaged: true)
            if !mounted.isEmpty {
                Task {
                    await self.lockAllVaultsNow()
                }
            }
        }
    }
}
