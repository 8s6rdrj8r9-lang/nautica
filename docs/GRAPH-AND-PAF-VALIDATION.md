# Validation results — September 30, 2026

## Build

Command:

```sh
xcodebuild -project Nautica.xcodeproj -scheme Nautica -configuration Debug -derivedDataPath DerivedData build
```

**Passed**, including the final UI focus/layout changes. The built application is `DerivedData/Build/Products/Debug/Nautica.app`.

The starting workspace contained uncommitted work. Four small compatibility fixes were necessary to compile that existing work: provide `FileItem.formattedSize`; handle optional file sizes in Hex Viewer and Secure Delete; supply the three missing browser-action callbacks. Existing work was preserved. No commit, installation into `/Applications`, or release deployment was performed.

## Automated checks

| Check | Actual result |
|---|---|
| Graph/PAF targeted tests | 8 tests passed, 0 failures |
| Full suite | 46 tests executed; 9 failed assertions in 3 tests |
| Baseline reproduction | The same 3 tests / 9 assertions failed in a separate temporary checkout of original HEAD |
| Whitespace validation | `git diff --check` passed |

The baseline failures are:

- `BatchRenameTests.testSequenceRenameWithHashes` — 3 assertions.
- `BatchRenameTests.testSequenceRenameWithoutHashesAppendsDigits` — 2 assertions.
- `FileOperationServiceTests.testCopyPreservesDanglingDestinationSymlink` — 4 assertions, including an unwrap failure.

The graph/PAF checks cover relationship persistence across store reopening, shared Object identity across Views, Collection/Smart/Relationship and combined queries, inferred-edge handling, View/pin removal without target deletion, pin ordering, subsystem registration, historical revisions, captured evidence stability, immutable storage enforcement, rejected incomplete/tampered packages, explicitly bounded projections, stale-review rejection, explicit freeze, transcript and expected-answer exclusion, clean-context export, response-marker validation, exact frozen report storage, supported artifact indexing, and preservation after subsequent graph/evidence edits.

Local command logs are retained in `build/graph-validation/`:

- `build.log`
- `graph-paf-tests.log`
- `all-tests.log`
- `baseline-tests.log`

## Real package

The user supplied the newer `PAF-v0.1-Auditor-Kit-Interactive-v1.1.zip`; this was used instead of the initially requested v1 filename.

- Original archive SHA-256: `563256d78e2f58a6e29b254de8ab0fa7f53a87cb806d40382ac8985004195c3a`.
- All **64 listed file checksums verified**.
- Manifest, entry points, templates, and framework coverage passed the host checks.
- Original archive bytes were verified against the immutable stored copy in the integration test.
- Real-package integration exercised draft persistence, projection review, freeze, and clean export using explicitly synthetic input.
- The real package was also imported through the running desktop UI into the local Nautica store, then observed again after app relaunch.
- Regression/expected files exist in the supplied archive. They are preserved in package storage but excluded from the clean auditor export, along with intake prompts and private intake transcript.

Checksums establish byte consistency, not publisher authenticity or methodological validity.

## Desktop checks

Observed in the built app:

- Objects & Views workspace and PAF workspace open.
- New Collection builder creates `Workshop` and pins it.
- Settings → Right Dock exposes enable/labels/presentation, View/Object/subsystem/action pinning, configuration, reorder, and removal controls.
- PAF appears in the registered-subsystem menu and can be pinned.
- Workshop and PAF pins persist after quitting and relaunching the app.
- Clicking Workshop opens that View; Down moves focus to PAF and Space activates it.
- Expanded pins are centered on the right edge within the window content.
- Package UI reports the v1.1 kit, exact archive hash, and 64 verified checksums.

The UI checks left an empty Workshop Collection and its pin, a PAF pin, and the imported package in the local app. No synthetic audit or synthetic evidence was added to the user's graph; lifecycle test data lived in temporary stores.

No VoiceOver session, exhaustive resize matrix, or external auditor execution was performed. The settings controls and Dock have native accessibility labels; the UI was inspected through screenshots and the accessibility tree.

## Execution boundary and remaining limits

The completed adapter is **manual standalone export / frozen-response import**. There is no embedded LLM runner. Intake is a grouped local form driven by user-supplied context, with package intake instructions available; it does not automatically inspect documents and generate conversational follow-up questions.

`AUDITOR RESPONSE FROZEN` capture and report-derived graph indexing passed with an explicitly synthetic test report. **No independent audit was performed and no real auditor response was captured.** There was no real audit subject/proposition supplied for execution. External auditor context isolation remains an explicitly recorded provenance limitation.

Historical queries reproduce state that Nautica has recorded. They cannot reconstruct dates before graph registration. File references are keyed by canonical URL; external file moves do not automatically relocate a registered reference. The graph engine currently evaluates local snapshots in memory.
