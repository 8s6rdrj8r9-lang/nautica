# Implementation Prompt: Nautica macOS 27 Modernization
**Target:** macOS 27.0.1 (Golden Gate)  
**Architecture:** Apple Silicon (ARM64) Exclusive | Swift 6.4 | SwiftUI + AppKit + SwiftData  
**License:** GPL-2.0 or later  
**Governance:** EnsDev Doctrine (Offline-first, Zero telemetry, Augmentation over automation)

---

## Objective
Modernize **Nautica** to target macOS 27 with:
1. **Default AI:** Apple Foundation Model (`FoundationModels`) on-device as the default AI assistant for folder summaries, smart tagging, and content analysis.
2. **Siri AI Delegation:** Native `AppIntents` integration supporting macOS 27 Contextual File Queries (right-click / Siri queries on files and directories).
3. **ChatGPT Backup:** Opt-in fallback to ChatGPT (OpenAI) when on-device models need cloud capabilities or complex multi-file reasoning, governed strictly by user consent.
4. **macOS 27 Features 1–6 Integration:**
   - **Feature 1 (AI & Contextual Delegation):** Built-in `AIService` with Foundation Model default, Siri AI Contextual File Query intents, and ChatGPT backup.
   - **Feature 2 (SwiftData Observers & Persistence):** `FolderViewState` decoupled with observation patterns for background actor services.
   - **Feature 3 (SwiftUI/AppKit Performance & Chrome):** Content prefetching, lazy-loading subviews, responsive toolbar modifiers (`toolbarOverflowMenu`, `visibilityPriority`), and Liquid Glass styling.
   - **Feature 4 (Apple Silicon Exclusivity):** ARM64-only optimization, unified memory streaming for directory indexing and thumbnail caching.
   - **Feature 5 (Full Disk Access & Transparency):** Modernized onboarding flow for macOS 27 user consent controls and agent protection guidelines.
   - **Feature 6 (Neurodivergent Spatial Consistency):** Predictable navigation, customizable density, and accessibility compliance.

---

## Detailed Requirements & Implementation Steps

### 1. AIService & Settings
- Create `Nautica/Services/AIService.swift`:
  - `AIService` singleton actor managing file operations AI:
    - `summarizeDirectory(at: URL) async throws -> String`
    - `suggestTags(for: URL) async throws -> [String]`
    - `explainFile(at: URL) async throws -> String`
  - Primary provider: On-device `FoundationModels` (zero network, zero telemetry, instant local inference).
  - Backup provider: ChatGPT (OpenAI) when configured with API key and user consent.
- Update `Constants.swift`:
  - Add keys: `aiEnabled`, `aiProvider`, `aiBackupProvider`, `openAIAPIKey`.
- Update `SettingsView.swift`:
  - Add an "Intelligence" tab or section allowing users to configure on-device Apple Foundation Models and optional ChatGPT backup.

### 2. Siri AI Delegation via App Intents
- Create `Nautica/Intents/NauticaAppIntents.swift`:
  - `SummarizeDirectoryIntent`: Allows Siri AI to summarize directory contents in Nautica.
  - `TagFilesIntent`: Contextual file action allowing Siri or context menus to apply tags.
  - `SearchFilesByContentIntent`: Natural language file search delegation.
  - Register with `AppShortcutsProvider`.

### 3. Full Disk Access Onboarding
- Update `OnboardingView.swift` and `FullDiskAccess` utility to reflect macOS 27's enhanced user prompt controls, clarifying the local-only guarantee and guiding the user seamlessly through System Settings without permission fatigue.

### 4. SwiftUI & SwiftData Modernization
- Adopt toolbar layout resilience (`visibilityPriority`, `toolbarOverflowMenu`) in toolbar chrome.
- Implement model observation pattern for `ViewStateService`.

### 5. Verification
- Verify compilation and code cleanliness under Swift 6.4 targeting `arm64-apple-macosx27.0`.
