# Nautica UI consistency repair — 2026-10-15

Authorization: owner requested implementation following the read-only UI/UX audit and supplied Files, Objects & Views and PAF screenshots. Scope is repairs to existing workflows; no release or installed-app replacement is authorized by this record.

Baseline: source commit 2d3428cf0190d96c141fcd9d58e2def4bef1c54c. Requirements: PRD US-NDC-03 (stable navigation), F-019 (native toolbar resilience), usability/accessibility section; Constitution AI Is Opt-In and Preservation Over Perfection; Doctrine Adaptive, Not Amputative Simplicity; Handbook Accessible and truthful operation feedback. Governance baseline: six-source manifest from EnsDev-Governance-2026-10-04-r3/current verified during audit. This is a bounded repair record, not an amendment or release approval.

## Changes

- Native toolbar workspace picker provides a consistent vertical location and native selected-state semantics; New View is contextual to Objects & Views. Native file toolbar capabilities remain available.
- Object action menu is content-sized; search has a clear action; empty/no-results states have useful actions; counts sit below the flexible content region.
- PAF has an actionable first-run state and nearby workflow guidance; its title uses the same hierarchy as Objects.
- Pinned-navigation scope is explained separately from Files Inspector; empty pins link to Settings. Inspector buttons use action names and selected accessibility traits. Glyphs use semantic text styles.
- Recents and favorites share a friendly iCloud Drive name.
- Appearance identifies Files-specific sizing and supports Columns as a default; Settings can grow rather than enforcing a fixed frame.
- Git status subprocesses run off the main thread and outside SwiftUI body evaluation, with cancellable periodic refresh and URL checks. This addresses the observed rendering/reentrancy risk; crash elimination remains unverified.
- AI is off for fresh settings; local-only is the safe default. Cloud requests require current versioned disclosure acceptance and an explicit cloud choice at the service boundary, regardless of legacy provider/fallback settings. Consent does not enable fallback automatically. Existing unversioned cloud settings do not qualify as consent.
- OpenAI keys use Keychain. Legacy preference keys are deleted only after successful Keychain storage/read. Replacement and removal controls never display the stored key. Keychain failure leaves migration incomplete and reports an error. Existing keys are migrated when Intelligence settings are opened or a consented cloud request needs a key.
- Foundation Models response uses the installed SDK's content API rather than the obsolete text member.
- Reset requires confirmation, reports persistence errors, and only shows success after save.
- Stale AI tests referring to APIs absent from the service are replaced with isolated preference-policy tests, covering defaults, legacy settings, current consent, local-only override, stale consent and disabled AI.

## Evidence and limits

- Swift parsing of changed sources: passed.
- Compiled and executed actual AIService with a minimal Constants fixture: seven cloud-authorization scenarios passed; no cloud calls or production credentials were used.
- Workspace shell, graph browser, view builder and empty PAF UI typecheck passed against macOS 26.5 SDK with storage/browser dependencies stubbed. Settings UI typecheck passed with service/storage dependencies stubbed; this is not integrated persistence verification. Git service and the actual status snapshot typechecked with the real Git state type.
- Full Xcode build/test and native visual verification: unavailable because no full Xcode installation is present. The active developer directory is CommandLineTools. SwiftUI typecheck with the default SDK is blocked by missing SwiftUIMacros; subset checks with an available older SDK are recorded in the delivery notes.
- Keychain migration, actual VoiceOver/focus behavior, narrow toolbar overflow, populated PAF/graph rendering, reset persistence failure and repeated workspace-switch stability still require integrated app verification. No compliance or release claim is made.

## Acceptance / next verification

Build with Xcode and run the test target; test fresh and legacy settings without enabling cloud traffic; confirm cloud routes remain denied for missing/stale consent and local-only mode; verify Keychain migration/removal with disposable credentials. Inspect Files/Objects/PAF at normal and narrow widths, light/dark and larger text; verify selected workspace and Inspector tabs with VoiceOver and keyboard. Navigate repeatedly between workspaces and directories, checking for crashes and preserving Files state. Confirm reset cancellation and truthful failure/success using disposable folder state.

Remaining broader design work: a unified app-wide density model and deeper progressive disclosure in specialist editors need a separate measured pass after the repaired baseline is built. Existing manual Files density controls remain available.
