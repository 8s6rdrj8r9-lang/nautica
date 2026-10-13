# Nautica alternatives and proposed concepts

**Advisory, frozen 2026-10-07.** These suggestions respond to the current audit. They are not adopted requirements, authorized implementation work, closure conditions or release approval. Effort is qualitative relative complexity, not a time or cost estimate. “Novel” means proposed for this inspected Nautica baseline; global originality was not investigated.

My recommended direction is a dependable file manager with optional, well-connected Objects and audit workspaces. Nautica's potential distinction is understandable operations and useful provenance under user control. The current defects make trust and recovery a more valuable next investment than additional surface area. Keep expert features discoverable, and give a new user an explicit place to start.

## Eight practical alternatives

### A-01 — A workspace choice with Files as the suggested starting point

**Problem:** the observed first-use screen opens an empty Objects workspace, while the draft product purpose is file management. **Alternative:** offer Files, Objects and Audits during first use; remember the user's choice and support stable switching. Keep density presets independent of workspace selection. This retains all capabilities and accommodates different purposes.

**Benefit:** users can reach their job without first learning graph vocabulary. **Tradeoff:** three workspaces still need shared search and clear selection/focus rules; excessive switching could fragment work. **Effort / dependency:** moderate UI/state work after the Files crash is repaired. **Cheap evaluation:** ask new and experienced users to locate a folder, make a Collection and import an audit package from a clean profile; observe wrong turns and comprehension. Set success criteria before the study rather than inventing a pass percentage afterward. Related: flow steps 4–9, F-01/F-15.

### A-02 — One preservation-focused operation engine

**Problem:** ordinary copy has useful staging, but Replace and sync bypass preservation through pre-deletion. **Alternative:** common operation plans with source/destination identity, staged publication, explicit collision policy, recoverable displacement where feasible, postconditions and per-item outcomes. Use platform file coordination for participating access, while designing replacement/recovery semantics separately. [Apple Foundation reference](https://developer.apple.com/documentation/foundation/nsfilecoordinator).

**Benefit:** copy, move, sync and later utilities can share safety and accounting rather than duplicating it. **Tradeoff:** temporary space, recovery data and more complex cross-volume/provider cases. Recovery storage must have retention limits and honest unavailable states. **Effort / dependency:** high; requires a decided batch-cancel policy, identity/race handling and filesystem-specific limits. **Cheap evaluation:** first route Replace and sync update through a minimal shared path, then rerun R-004 fixtures plus denied-read/interruption controls. Related: F-02/F-03/F-04/F-16. Architecture alone is not closure evidence.

### A-03 — A shared queue and searchable action registry

**Problem:** concurrent work, cancellation policy and repeated shortcut declarations are hard to understand. **Alternative:** a queue shared across windows with explicit queued/running/paused/partial states, plus a single action registry feeding menus, bindings and a searchable chooser. Avoid duplicate key bindings before dispatch; allow user-defined bindings with visible conflicts.

Marta documents both a shared operation queue with keyboard pause/cancel and a configurable action system. Those are useful patterns, without proving its recovery behavior or Nautica parity. [Marta queue](https://marta.sh/docs/core/operation-queue/), [Marta actions](https://marta.sh/docs/core/actions/).

**Benefit:** predictable access and one place to inspect work. **Tradeoff:** a strict global queue can slow independent volumes; cancellation and pause differ and must be explained. **Effort / dependency:** moderate for registry, high for robust queue; start with explicit per-volume concurrency limits. **Cheap evaluation:** test two-window duplicate requests, cancel a multi-item job and invoke commands from different focus states. Related: F-15/F-16; preserves expert access while simplifying discovery.

### A-04 — Sync as a reviewed change plan

**Problem:** a preview can be invalidated by missing roots or changed sources, and metadata equality is overstated. **Alternative:** a preview stating additions, updates and deletions, readable root identity/availability, fast versus verified comparison, excluded items and a revalidation policy. When either root changes materially, refresh and explain the differences before destructive execution.

ForkLift's manual documents sync previews with change counts, exclusions and saved configurations, alongside configurable panes. Use that as a concrete comparison for review clarity, not proof of safer implementation. [ForkLift manual](https://www.binarynights.com/manual).

**Benefit:** users see consequence and comparison confidence. **Tradeoff:** hashing and revalidation cost time; source changes cannot be prevented just by showing a preview. **Effort / dependency:** moderate UI, high engine changes through A-02. **Cheap evaluation:** disconnect a synthetic root, mutate a source between compare/execute, and compare identical metadata with different bytes. Related: F-03/F-04/F-05. A confirmation cannot authorize destruction based on an inaccurate plan.

### A-05 — Honest deletion and scoped vault protection

**Problem:** overwrite wording promises more protection than supported, file links reach unselected targets, and vault automation discovers system images. **Alternative:** distinguish Move to Trash, Permanent Delete and a narrowly described overwrite operation only where meaningful. Explain storage limitations at the point of use. Maintain a registry of explicitly managed vault identities, gracefully detach only those, and report busy/failed locks without claiming success.

Apple's storage guide states that secure-erase options are unavailable for SSDs and points to FileVault protection from initial use. That does not establish per-file forensic erasure. [Apple Disk Utility guide](https://support.apple.com/en-il/guide/disk-utility/-dskutl14079/mac). Keychain user-presence constraints are a platform option for a selected credential-access policy. [Apple Security reference](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence).

**Benefit:** users can reason about scope and protection. **Tradeoff:** fewer impressive claims; key policy and accessible authentication/recovery need explicit choices. A busy-volume prompt can interrupt work. **Effort / dependency:** high validation burden, moderate labels and registry work; define threat and recovery boundaries first. **Cheap evaluation:** disposable file links, unrelated images, duplicate volume names, busy files and failed verification. Related: F-06/F-08/F-09/F-11. Do not claim cryptographic erasure unless the controlled key lifecycle, copies and storage boundary establish it.

### A-06 — Name the embedded shell runner honestly, or provide a PTY

**Problem:** Nautica's inspected embedded panel runs individual shell commands; it has no PTY or interactive input loop. **Alternative:** call it a Command Runner and show working directory, running state, stop action and bounded output; keep external-terminal handoff. If interactive terminal use is a real product requirement, add a proper PTY session with deliberate process and directory synchronization.

Marta documents pane-associated embedded PTY behavior and directory synchronization. This defines a useful capability contrast rather than a parity requirement. [Marta terminal documentation](https://marta.sh/docs/advanced/terminal/).

**Benefit:** expectations match capability, and existing external terminals remain usable. **Tradeoff:** PTY integration adds process cleanup, output handling, input accessibility and security complexity. **Effort / dependency:** small-to-moderate for runner clarity; high for terminal sessions. **Cheap evaluation:** interactive input, long output, canceled child processes, invalid working directory and pane switching in a disposable environment. Terminal tasks were not executed in this audit.

### A-07 — Make Drop Shelf a staging tool with explicit effects

**Problem:** temporary selection across folders is valuable, but stale references and ambiguous move/copy behavior can undermine trust. **Alternative:** keep references on the Shelf until a named Copy Here, Move Here or Create Collection action; indicate missing/moved items, scope and the destination. Clearing a staged reference should not imply file deletion.

Path Finder documents a temporary Drop Stack before an explicit file action. That supports the staging pattern, not a guarantee of Nautica's identity semantics. [Cocoatech Drop Stack documentation](https://support.cocoatech.com/hc/en-us/articles/43505869579796-Drop-Stack-Temporary-Holding-Area-for-Files).

**Benefit:** collecting files is separable from consequential movement, and Collections can reuse the mental model. **Tradeoff:** reference reconciliation and persistent paths need privacy/retention controls. **Effort / dependency:** moderate; stable identity and A-02 outcomes help. **Cheap evaluation:** stage files from two folders, rename one externally, remove another, then review the proposed action. Keep stale items visible until deliberately removed. Browser Shelf UI was not demonstrated here.

### A-08 — Media preservation and rename recovery as differentiators

**Problem:** MP3 edits drop untouched fields; a basic batch rename no longer distinguishes Nautica from Finder. **Alternative:** selective media-field merging with preservation reports and supported-format limits; rename templates with old/new preview, collision explanation, exact extension handling and a recoverable manifest. Use mature format support or preserve opaque fields rather than rebuilding only familiar ones.

Finder already includes multiple-file text replacement, addition and formatting. Differentiate on clarity, verified preservation and recovery rather than claiming that baseline is absent. [Apple Finder guide](https://support.apple.com/en-ph/guide/mac-help/-mchlp1144/mac).

**Benefit:** professional users can trust bounded changes. **Tradeoff:** format/library maintenance, retained originals and backup space; preservation reports must avoid collecting unnecessary sensitive metadata. **Effort / dependency:** moderate-to-high; format contracts and A-02 help. **Cheap evaluation:** one-field edits with unknown ID3 frames/artwork and real playback; rename cycles, same-name collisions, Unicode and externally moved files. Related: F-07 and legacy rename-test discrepancies.

## Ten concepts to explore after the urgent repairs

### N-01 — Operation Receipts

Give a completed or partial operation a small inspectable receipt: intended scope, exact action, completed/skipped/failed counts, recovery availability and observed postconditions. Allow an optional relationship to a project Object or audit Finding. A hash or timestamp should support only the property actually checked.

**Why it fits:** Nautica already has graph identities and PAF records. **Benefit:** a user can answer “what happened to these files?” without a technical log. **Feasibility:** moderate once A-02 provides outcomes. **Constraint:** file paths and past actions are personal data; inspection, retention, export and erasure must be usable, and receipts must not silently log every action. **First experiment:** show receipts for three synthetic outcomes—success, partial cancel and failed replacement—and ask users to identify what remains. No embedded AI is needed.

### N-02 — Change Budgets for mirror sync

Let a reusable sync configuration specify an intelligible consequence limit, such as maximum deletions or changed data, with deletions disabled by default for a new relationship. If the proposed plan exceeds the user-selected budget, stop and explain which changes caused it. Budget overrides are explicit for that reviewed plan and do not persist silently.

**Why it fits:** this turns an unexpected empty/disconnected root into a visible exception after root validation, rather than a broad deletion. **Feasibility:** moderate around a reliable planner. **Constraint:** a small budget does not make an invalid plan safe; missing-root rejection and execution revalidation remain essential. **First experiment:** compare normal daily changes with missing-root and mass-rename fixtures; show the plan difference and explain why execution is blocked. Thresholds come from the user's workflow, not an invented universal number.

### N-03 — Purpose Envelopes for audit exports

Before exporting PAF context, show a compact envelope naming purpose, selected records/files, recipients, sensitive fields and snapshot time. Offer omission/redaction, a usable preview and an optional reminder to remove the local exported copy. A later import can retain the envelope as declared context rather than treat it as new authority.

**Why it fits:** PAF already separates export and external evaluation. **Feasibility:** moderate; versioned format and field selection required. **Constraint:** an expiry date cannot enforce deletion by an external recipient; state shared-copy limitations. Do not auto-authorize new access or export extra graph history. **First experiment:** export synthetic evidence with paths and unrelated notes, then verify the receiver sees only the chosen subset and understands what was omitted.

### N-04 — Recovery Diff

Before Undo or restoration overwrites anything, show what changed since the original operation: current target, retained previous target, new conflicts and the subset that can still be recovered. Offer Restore Elsewhere when safe in-place restoration is no longer possible.

**Why it fits:** preservation and deliberate deletion both require more than a generic Undo label. **Feasibility:** high; reliable receipts, retained versions and identity tracking required. **Constraint:** do not reintroduce deliberately deleted personal content through stale backup recovery; define expiry and authorized restoration. **First experiment:** copy, edit the destination afterward, then request Undo. Users should be able to see the conflict and recover old work without losing their new edit.

### N-05 — Evidence Freshness

Let Objects and PAF evidence distinguish a frozen snapshot from a live file reference. Show Current, Changed, Unavailable or Not Checked with the last observed check and method. Refresh is explicit; changed live files never silently alter frozen audit evidence.

**Why it fits:** hashes and graph history already exist. **Feasibility:** moderate, with on-demand checking before background monitoring. **Constraint:** freshness is not accuracy or authenticity; checking incurs I/O and may access sensitive files. Unavailable must not be relabeled deleted. **First experiment:** mutate, move and disconnect disposable referenced files; verify the original snapshot stays intact and the UI explains the present relationship.

### N-06 — User-locked workspaces for different attention needs

Provide named, editable presets such as Everyday Files, Compare & Transfer, Media Review and Audit Desk. Presets change density and visible tools while keeping capabilities findable through stable actions. Users can lock their layout; no automatic rearrangement occurs during active work.

**Why it fits:** existing dock modes, pins and pane configurations supply much of the state. **Feasibility:** moderate. **Constraint:** a simplified preset must not remove keyboard access or hide irreversible consequences; all presets need accessible labels and predictable focus. **First experiment:** compare clean-profile task completion and task resumption with locked versus constantly adapting layouts. Include people with differing attention, motor and visual needs; do not infer accommodation from developer preference.

### N-07 — Disposable Rehearsal

Offer an optional rehearsal of a rename or sync plan on an explicitly selected synthetic or duplicate fixture, producing a receipt of what actually ran. Distinguish simulation, duplicate-data execution and real execution prominently.

**Why it fits:** current operations are consequential and plan inspection alone misses execution failures. **Feasibility:** moderate for rename, high for large/provider sync. **Constraint:** duplication costs space, copies sensitive data and cannot reproduce every real permission, device or provider condition. Rehearsal success is not a safety guarantee. **First experiment:** generate synthetic fixtures by default; introduce stale sources and naming conflicts to demonstrate which outcomes a plan-only preview would miss. Never automatically clone a user's entire private dataset.

### N-08 — Workspace Exit Capsule

Export selected Objects, Views, relationships, audit records and user-created workspace settings in a documented versioned package, with optional separately selected file copies. Include a human-readable inventory and instructions for resolving file references on another installation. Import should show unsupported fields and migration effects before changing state.

**Why it fits:** current graph ownership/portability is the largest lifecycle target gap. **Feasibility:** high; schemas, migration and deliberate-deletion rules must precede a polished export button. **Constraint:** references, evidence blobs and keys have distinct handling; omit secrets, prevent unintended disclosure and test restoration. **First experiment:** export a small synthetic workspace, import into a clean profile and compare represented data/settings. Demonstrate supported exit outside Nautica, not merely a backup that only the same instance can reopen.

### N-09 — A separate recovery workspace

Provide a deliberately selectable recovery launch mode that can open a basic file browser or export surviving records without loading a damaged/unsupported optional graph store. Display the disabled capabilities and offer a recoverable copy of diagnostic state.

**Why it fits:** the Files entry currently shares a crashing shell path. **Feasibility:** high architectural separation; repair the observed crash first. **Constraint:** a process-level layout crash cannot be solved by a decorative in-app error banner, and the proposed mode is not evidence that the present crash is caused by graph corruption. Avoid silently resetting user stores. **First experiment:** exercise a separate window/root and unsupported synthetic database; prove unaffected tasks operate and original bytes are preserved. Escalate undecodable evidence rather than invent content.

### N-10 — Explainable duplicate choices

For a duplicate group, explain byte-verification method, unavailable checks, aliases/hard links, locations and estimated reclaimable storage. Offer a user-selected keeper policy and a recoverable action plan; revalidate identity immediately before any deletion.

**Why it fits:** the size/prefix/full-hash pipeline already passes a small control. **Feasibility:** moderate with better identity/storage accounting and A-02. **Constraint:** logical equal size does not guarantee physical reclaimed space; snapshots, clones and links affect the estimate. A suggested keeper is not a fact about importance. **First experiment:** exact duplicate files, same-size different bytes, hard links, APFS clones and stale results. Explain estimates and protect newly changed or unselected data. No automatic AI cleanup is needed.

## How to choose

First fund the common controls needed by several ideas: reliable staged replacement, exact identity, truthful per-item outcomes, clear current scope and usable retention/portability. Next, N-01 receipts and N-05 freshness fit the existing graph/PAF architecture and can be piloted on synthetic work. N-02 budgets strengthen sync only after root validation is fixed. N-06 workspace presets improve first-use clarity after Files is operable. N-08 addresses a substantive target gap rather than being merely a novelty feature.

Defer broad autonomous cleanup, forced system-wide vault management, more encryption marketing and extra shell capability until their existing authority, recovery and protection claims are settled. Each adopted concept should receive explicit purpose/scope, affected-person and retention review, criteria and proportionate verification. Suggestions do not amend the frozen PRD or EnsDev corpus.

Evidence grounding: [AUDIT-REPORT.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/AUDIT-REPORT.md) · [FEATURE-REVIEW.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FEATURE-REVIEW.md) · [FLOW-REVIEW.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FLOW-REVIEW.md) · [EXTERNAL-SOURCES.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/EXTERNAL-SOURCES.md).

AUDITOR RESPONSE FROZEN
