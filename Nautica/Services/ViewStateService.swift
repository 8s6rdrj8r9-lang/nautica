import Foundation
import SwiftData

/// Per-folder view state persistence (Prompt 12). Loads (or creates) the
/// `FolderViewState` for the current folder and saves changes, debounced by
/// 500 ms so rapid slider drags don't hammer the store.
@MainActor
@Observable
final class ViewStateService {
    private let context: ModelContext
    /// State of the folder currently shown.
    private(set) var current: FolderViewState?
    private var saveTask: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
    }

    /// Returns the stored state for `folderPath`, creating a default one on
    /// first visit, and makes it current.
    @discardableResult
    func state(for folderPath: String) -> FolderViewState {
        let descriptor = FetchDescriptor<FolderViewState>(
            predicate: #Predicate { $0.folderPath == folderPath }
        )
        let state: FolderViewState
        if let existing = (try? context.fetch(descriptor))?.first {
            state = existing
        } else {
            // First visit: inherit the global hidden-files default (Prompt 14).
            state = FolderViewState(
                folderPath: folderPath,
                showHiddenFiles: UserDefaults.standard.bool(forKey: Constants.showHiddenFilesKey)
            )
            context.insert(state)
        }
        state.lastVisited = .now
        current = state
        return state
    }

    /// Inserts a new state if needed and saves immediately.
    func saveState(_ state: FolderViewState) {
        if state.modelContext == nil {
            context.insert(state)
        }
        try? context.save()
    }

    /// Saves the current state after a 500 ms quiet period.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [context] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? context.save()
        }
    }

    /// One-time migration from a UserDefaults-based schema. There is no
    /// earlier persisted format, so this is intentionally a no-op.
    func migrateFromUserDefaultsIfNeeded() {}
}
