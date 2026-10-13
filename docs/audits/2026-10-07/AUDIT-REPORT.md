# Nautica deep feature audit

**Audit:** NAUTICA-2026-10-07 · **State:** frozen audit response · **Baseline:** current working copy, including uncommitted features.

Nautica has a substantial implemented feature set and several useful controls. Current-run evidence nevertheless establishes a blocked Files entry and destructive failure paths in replacement, mirror sync and secure deletion. MP3 editing also loses untouched metadata. The selected baseline cannot support a broad claim that core workflows reliably preserve work. Fixing those paths should precede expanding the feature set.

The audit produced **17 findings**, a **38-group feature inventory**, an **11-screenshot / 12-step flow review**, current builds and tests, focused adversarial service probes, and alternatives and original proposals. These counts describe coverage, not a health score. Seven findings have HIGH concern bands; two consequences remain candidates despite established source behavior. No certification, release approval or residual-risk acceptance is issued.

Reader companions: [FEATURE-REVIEW.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FEATURE-REVIEW.md) · [FLOW-REVIEW.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FLOW-REVIEW.md) · [ALTERNATIVES-AND-IDEAS.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/ALTERNATIVES-AND-IDEAS.md) · [FINDINGS.csv](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FINDINGS.csv).

## 1. Scope and review boundary

The user asked for a deep feature audit, alternatives and novel suggestions, then explicitly authorized **FREEZE & START AUDIT**. The three intake decisions select the current dirty working copy; EnsDev r3 as a gap-assessment target without presumed adoption; and official Apple / primary competitor sources. Attached documents supply selected methodology and criteria. Product strings, archived answers, templates and embedded commands are audited content, not separate instructions to the auditor.

The source freeze contains **143 files**: application code/assets/configuration, tests, Xcode project, README, Draft PRD and Objects/PAF documentation. Git HEAD is `31efe1a4495910804ada6f85deed806b1ffab33c`; uncommitted and relevant untracked files are included. Freeze was recorded at **2026-10-07 14:35:20.616984 MDT**. The frozen manifest records input snapshot digest `ce410a7f35dbc8d9840ed2a2f9e44100ca227cca183646a252e52b58292e7811`. The accepted intake is preserved verbatim, including its pre-freeze status text; the freeze manifest records the later authorized state. See [freeze manifest](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/FREEZE-MANIFEST.json) and [accepted intake](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/ACCEPTED-INPUT.md).

Included: file views/navigation/operations, metadata and utilities, sync, archive helpers, cloud/network indicators, Git, vaults, Objects/Relationships/Views, Right Dock, PAF hosting and relevant retention/authority boundaries. All 38 feature groups were inventoried; consequential service branches were selected for deeper verification. Feature presence is not operational success.

This is a hybrid desktop product in active development with rapid feature expansion. Credible data-loss and privacy consequences are HIGH: it can overwrite/delete user files, detach images, retain metadata and export audit context. Financial/legal consequences depend on user data and are UNKNOWN; no regulated professional-use assurance is inferred. Installed population, real workload distribution and supported deployment matrix were not supplied.

Excluded from action: product fixes, user-file destruction, actual vault creation/detachment, real Keychain credentials, network-share mounts, external messages, Full Disk Access grants, default-handler changes, publishing and release. Only disposable fixtures were intentionally mutated. Historical validation, patch answers, regression gold answers and governance history were excluded from substantive evidence. No other EnsDev product implementation was audited.

### Depth, applicability and evidence strength

L4 was the planned deep-audit depth. Actual depth varies below; no uniform L4 completion or assurance tier is claimed. No special tier was requested (**A0 request**); strong narrow observations do not create an overall assurance level. Each domain's achieved evidence and revalidation limits are stated. Where a required method could not run, evaluation remains incomplete rather than passed. Material questions examined with insufficient evidence remain inconclusive.

| Universal domain | Applicability | Planned → performed depth | Achieved evidence / limitation |
| --- | --- | --- | --- |
| U01 Intent & Purpose | REQUIRED | L4 → L3 | Draft purpose and all feature groups mapped; onboarding/default-workspace mismatch; broad user validation absent. |
| U02 Requirements & Specification | REQUIRED | L4 → L3 | Draft authority retained; performance/cancellation/network/keychain conflicts identified; approved current PRD absent. |
| U03 Architecture & Design | REQUIRED | L4 → L3 | Graph shell, service boundaries, persistence and direct tool invocation reviewed; layout root cause UNKNOWN. |
| U04 Correctness & Fitness | REQUIRED | L4 selected / L3 overall | Adversarial fixtures establish specific destructive outcomes; core browser tasks and many media/provider cases incomplete. |
| U05 Quality & Robustness | REQUIRED | L4 selected / L3 overall | Missing/stale roots, links, partial results and control checks challenged; full interruption/storage matrix untested. |
| U06 Human Factors & Usability | REQUIRED | L4 → L3 | 12 steps with accepted screenshots/blocker; no participant study or full browser journey. |
| U07 Accessibility & Inclusion | REQUIRED | L4 → L2 | Visible text/focus and shortcut declarations reviewed; VoiceOver/accommodated core-task verification incomplete. |
| U08 Security & Abuse Resistance | REQUIRED | L4 selected / L3 overall | Link boundary and archive/vault/source authority reviewed; forensic deletion, authentic distribution and live credentials not verified. |
| U09 Maintainability & Operability | REQUIRED | L4 → L3 | Current builds/tests, service duplication, error handling and reproducible fixtures reviewed; support handoff not demonstrated. |
| U10 Performance & Capacity | REQUIRED | L4 → L3 service / L2 UI | 15k enumeration and 50k sort measured; paint/fps/window/preview/memory targets unresolved. |
| U11 Testing & Verification | REQUIRED | L4 selected / L3 overall | Original suite plus three harnesses; failing/skipped tests and synthetic-versus-current-kit distinction preserved. |
| U12 Lifecycle & Sustainability | REQUIRED | L4 → L3 | Graph retention/export, versioning and update/exit needs reviewed; restore/migration and retirement not demonstrated. |
| U13 Governance & Decisions | REQUIRED | L4 → L3 | Six current criteria versions traced; target gaps documented; adoption, approved PRD and operating decision records not established. |

| Conditional domain | Applicability | Reason / completed scope |
| --- | --- | --- |
| C01 Safety | REQUIRED | Data-preservation and accidental destructive action; selected L4 probes. No bodily-safety case established. |
| C02 Privacy | REQUIRED | Graph/evidence retention, scoped automation and protection claims; L3. Full data-flow and endpoint observation incomplete. |
| C03 Legal / Regulatory / Contractual | NOT_YET_DETERMINED | Jurisdictions, distribution and contracts absent. This is an applicability UNKNOWN, not a legal compliance finding. |
| C04 Accessibility Engineering | REQUIRED | Native core-task/input support warrants dedicated tests; L2 review only. Engineering verification incomplete. |
| C05 Human Factors / Ergonomics | REQUIRED | Complex forms, destructive confirmations, density and automation timing; L3 representative flow review. |
| C06 Data & Information Quality | REQUIRED | False identity, stale plans, metadata loss, truncation and health labels; selected L4 probes / L3 breadth. |
| C07 AI & Automation | REQUIRED | Rule/vault automation and PAF external execution boundary; L3. No embedded model runner observed. |
| C08 Ethics / Social Impact | RECOMMENDED | Agency, non-user information and differing needs assessed at L2; no representative fairness study. |
| C09 Reliability / Resilience / Recovery | REQUIRED | Selected L4 failure tests; rollback, backups and broader crash recovery incomplete. |
| C10 Interoperability / Compatibility | REQUIRED | Media, package entry points, native tags, providers and Git paths; L3 with selected probes. |
| C11 Dependencies / Supply Chain | REQUIRED | Resolved GRDB 7.11.1 and platform/system-tool dependencies recorded; L2 security review, no comprehensive advisory/license analysis. |
| C12 Financial / Economic | OPTIONAL | Qualitative sequencing only; no prices, ROI, budget or market-sizing conclusions. |
| C13 Environmental | OPTIONAL | Performance implications noted; energy/resource impact not measured. |
| C14 Research / Scientific Validity | NOT_APPLICABLE | Nautica is not presented as scientific measurement or research analysis; benchmarks still disclose methods. |
| C15 Records / Knowledge Management | REQUIRED | PAF and append-only graph records require retention/portability; L3 with host tests. |
| C16 Observability | REQUIRED | Partial results, errors, limits and diagnostic truthfulness; L3. |
| C17 Provenance / Traceability | REQUIRED | Frozen source/evidence hashes, package verification and history semantics; selected L4 examination. |

Ecosystem applicability: shared macOS/platform infrastructure, data/interchange contracts, inherited platform risks, change propagation and correlated failure are REQUIRED within this product boundary. They received L2–L3 review of platform APIs, package/schema contracts and shared operation paths. Inherited controls, cross-project governance and ecosystem resilience are NOT_YET_DETERMINED where they require actual other-product adoption, integration or recovery evidence. Other product implementations remain OUT_OF_SCOPE. A shared vocabulary does not establish cross-app compatibility or inherited assurance.

Stop conditions: the approved frozen boundary was examined; consequential reproducible questions received authorized fixture tests; the Files crash blocked further live browser steps; unavailable live-vault/provider/accessibility/deployment evidence was recorded. Specialist credential, cryptographic, filesystem-forensic and accessibility evaluations are not silently represented as performed. This audit pass is complete as a report of that execution; several required product evaluations remain incomplete.

## 2. Governing criteria

| ID / role | Criterion used | Frozen source |
| --- | --- | --- |
| M-1 / methodology | PAF Core, Evidence, Findings, Domains, Profiles, Risk and reporting; verification A/B/C/D | [PAF framework](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/methodology/framework/AUDIT-CORE.md) |
| I-1 / documented intent | Draft PRD v1.0, August 8, F-001–F-016, acceptance and non-functional clauses | [Draft PRD](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica-PRD-v1.0.md:1) |
| T-1 / target invariant | Human First; User Ownership; Preservation Over Perfection; Graceful Degradation; Privacy and Context Minimization | [EnsDev_Constitution.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Constitution.md:5) |
| T-2 / target strategy | Offline-First; Adaptive, Not Amputative Simplicity; User-Controlled Interoperability; Security and Privacy by Design | [EnsDev_Doctrine.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Doctrine.md:13) |
| T-3 / target engineering | AI and Automation Controls; Information and Affected-Person Review; five Definition of Done gates | [EnsDev_Engineering_Handbook.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Engineering_Handbook.md:5) |
| T-4 / target domain controls | Reliability and Data Integrity; Compatibility and Schema Evolution; Evidence for Product Claims | [EnsDev_Engineering_Handbook.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Engineering_Handbook.md:414) |
| T-5 / target decisions | Decision Authority; Product Specifications; adoption/versioned approvals and scope | [EnsDev_Governance.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Governance.md:40) |
| T-6 / target ontology | Common meanings, named product extensions and versioned mapping | [EnsDev_Ontology_Standard.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/criteria/EnsDev_Ontology_Standard.md:5) |

Current corpus: Manifesto 4.2, Constitution 6.0, Doctrine 2.1, Handbook 5.4, Governance 1.7, Ontology 4.0; six selected hashes match the supplied current corpus. The loader is a supporting entry mechanism, not an additional governing tier. Nautica adoption is not established by the supplied adoption register. P-4 therefore identifies target gaps, not retroactive nonconformance. No external accessibility, legal or security certification standard is substituted without selected applicability.

## 3. Evidence considered

Builds/tests ran in a writable temporary copy of frozen sources on Apple Silicon macOS 26.6.2 (25G83), Xcode 27.0 (27A266a). GRDB resolved to 7.11.1, revision `b83108d…` (the full pinned value is in Package.resolved). Source code was unchanged. UI bundles were instrumented for disposable-home launch and separate preferences; their signature bytes changed while executable text-section hashes matched the originals.

| Record | Current-run result | Evidentiary meaning |
| --- | --- | --- |
| R-001 / R-002 | [R-001-build.log](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-001-build.log); [R-002-test-build.log](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-002-test-build.log) | Debug build and test build succeeded; compilation is not workflow verification. |
| R-003 | [R-003-original-tests.log](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-003-original-tests.log) | 46 tests: 42 passed, 3 failed, 1 skipped; 9 assertion failures across 3 tests. No suite-pass claim. |
| R-004 | [R-004-behavior-probes.json](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-004-behavior-probes.json); [R-004-behavior-probes.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-004-behavior-probes.swift) | Actual frozen services: replacement, sync, selected links and ordinary-copy control; disposable canonical filesystem paths. |
| R-005 | [R-005-release-build.log](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-005-release-build.log) | Release build succeeded; runtime Files entry still crashed. |
| R-006 | [R-006-utility-probes.json](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-006-utility-probes.json); [R-006-utility-probes.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-006-utility-probes.swift) | Actual loader/media/checksum/duplicate services; synthetic ID3 and exact supplied package. Two GraphStore helper adapters copied verbatim; no GRDB persistence assurance from this harness. |
| R-007 | [R-007-capacity-rename-git.json](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-007-capacity-rename-git.json); [R-007-capacity-rename-git.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/R-007-capacity-rename-git.swift) | Optimized 15k service listing, 50k in-memory sort, current Custom Pattern rename and disposable Git status fixture. |
| U-003/U-004/U-006 | [U-003-files-crash-first.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-003-files-crash-first.ips); [U-004-files-crash-repeat.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-004-files-crash-repeat.ips); [U-006-files-crash-release.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-006-files-crash-release.ips) | Two Debug and one Release audit-identity crashes: EXC_BAD_ACCESS / SIGBUS, main-thread SwiftUI StackLayout path. Root cause UNKNOWN. |
| UI-01–11 | [FLOW-REVIEW.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/FLOW-REVIEW.md) | Accepted exact screenshots and 12 named steps; browser step blocked. Earlier inherited-pref screen rejected. |
| S-001 / source | [S-001-service-index.txt](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/S-001-service-index.txt); [frozen source](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source) | Static inspection grounds candidate concerns and presence; index alone is not exhaustive code verification. |
| X-01–09 | [EXTERNAL-SOURCES.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/EXTERNAL-SOURCES.md) | Current official Apple/competitor documentation for limited comparisons and alternatives; no competitor benchmark or price claims. |
| Integrity | [FINAL-INPUT-INTEGRITY.json](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/FINAL-INPUT-INTEGRITY.json) | All 143 original selected files match freeze; frozen inputs match their recorded hashes. |

The original failing tests comprise two legacy sequence-rename expectations and one dangling-destination-symlink naming expectation. The current `.sequence` alias maps to format mode; Custom Pattern is the mode that uses the supplied pattern and it produced `vacation_001.txt` through `vacation_003.txt` in R-007. The dangling-link copy failure was safe: exclusive publication rejected the occupied link; the link was not overwritten. Resolve these test/API expectations without mistaking every failed assertion for destructive behavior.

GraphStore's four tests, the three synthetic PAF host tests and named selection/split/cloud/tag controls passed. The optional real v1.1 package test was skipped because its environment input was absent. It is not evidence for the exact supplied legacy package. R-006 and live import show that package is not freeze-ready: the sidecar references absent `AUDIT-INTAKE.md` and `AUDIT-INITIATION-PROMPT-INTERACTIVE.md`. Sixty present checksums match; one referenced release source ZIP is not included. The separate TXT initiation document is available for this human-directed audit, but does not repair those product entry points. No kit files were fabricated or renamed.

Sampling was risk-directed rather than random: failures around destruction, stale inputs, metadata preservation and exact package compatibility; safe controls to challenge broad failure claims; all feature groups indexed. These fixtures establish pathways, not production incidence rates. No test-coverage percentage or statistical generalization is supplied.

### Adversarial challenge

| Claim challenged | Observed result | Disposition |
| --- | --- | --- |
| Build success implies safe core workflows | Debug/Release build succeed; Files crashes and four destructive scenarios reproduce | Rejected broad assurance inference. |
| Staged copy makes Replace safe | Ordinary copy succeeds; Replace removes the old target before failed staging | Control is real but does not protect this branch. |
| A missing mirror root is equivalent to empty | Missing-root plan deletes a right-side sentinel | Refuted; empty/readable versus unavailable must differ. |
| A mirror Identical result proves equal bytes | Equal size/time AAAA versus BBBB is skipped | Refuted for current fast comparison. |
| Every symlink permits recursive destruction | Selected file-link target truncated; directory-link probe throws and preserves child | File failure confirmed; broader directory claim not established. |
| Old sequence-test failures mean current Custom Pattern is broken | Explicit Custom Pattern generated expected names | Refuted broad claim; legacy default/API tests still unresolved. |
| Verified package checksums mean ready/authentic | Hashes match; two entry points missing; hash has no publisher authentication | Integrity is narrower than readiness or authenticity. |
| Synthetic host tests establish exact supplied-kit freeze | Host tests pass; current kit correctly blocks freeze | Refuted substitution of different fixtures. |
| Fast 50k sort establishes large-folder UX target | 37 ms sort; 15k complete listing 5.26–6.14 s; no UI timing | Full target remains unresolved. |

## 4. Proposition determinations

### P-1 — Feature coverage and specification fidelity

**Determination: mixed demonstrated coverage; broad specification fidelity INSUFFICIENT_EVIDENCE, with identified contradictions.** All 38 feature groups are traceable to source or current observation. Original F-001–F-016 priorities are mapped in the feature review. Onboarding, Object creation, Collection pinning, PAF import/blocking and settings operated. Source presence covers more than live demonstration. Several browser Must features could not be exercised after Files crashed.

Draft cancellation expectations disagree with completed-batch retention. The original no-cloud/no-network and restricted-Keychain scope no longer describes the expanded cloud/share/vault product. Finder batch rename is also mischaracterized in the draft. These need a current product specification, with the draft's authority status retained. **Achieved assurance:** strong for listed presence and narrow tasks; no general tier assigned. **Material UNKNOWNs:** full browser journeys, restore/migration, provider parity and the approved current requirement set.

### P-2 — Correctness, resilience and protection of work

**Determination: contradicted for the tested preservation and authority-boundary cases.** Replacement failure, missing-root mirror, stale-source sync and selected file-link deletion caused loss or truncation of synthetic bytes. MP3 single-field editing dropped an untouched artist frame. These outcomes are sufficient to reject broad work-preservation claims for the selected baseline, even though ordinary copy and several cleanup controls passed.

**Achieved assurance:** strong direct evidence for named fixture outcomes; broader reliability remains unestablished. **Material UNKNOWNs:** disk-full, permission changes, live vault locking, malicious archive extraction, crash rollback, hard links, real media fidelity and verified restoration. Vault automation and suppressed-error consequences remain candidate concerns. Required evaluations not performed are incomplete; they are not safe-by-default conclusions.

### P-3 — Usability, predictability and accessibility

**Determination: representative strengths and barriers established; core Files usability blocked; accessibility INSUFFICIENT_EVIDENCE.** The 12-step review records explicit permission skipping, Collection membership, successful pin navigation and honest manual PAF boundaries. It also records absolute protection copy, unfamiliar first-use orientation, unnecessary View-builder controls and shortcut conflicts. The Files crash prevents a complete principal task.

**Achieved assurance:** direct screenshot/interaction support for stated steps; source support for declared shortcut collisions. **Material UNKNOWNs:** VoiceOver, keyboard-only core operations, large text, measured contrast, reduced motion, browser focus behavior, user comprehension and full render latency. No WCAG, Apple accessibility or other comprehensive compliance claim is made.

### P-4 — EnsDev r3 target-baseline alignment

**Determination: partial alignment with confirmed target gaps; overall target alignment INSUFFICIENT_EVIDENCE.** Local/manual graph and PAF hosting, provenance hashes, explicit package blockers, immutable history and adjustable dock density are positive practices. Failure preservation, narrowly scoped automation, deliberate deletion/retention, usable general portability, honest protection claims and current product criteria need work.

Against the target five gates: Secure is not established, with a demonstrated selected-item boundary failure; Tested has failures and consequential untested paths; Documented lacks an established approved current scope and accurate affected claims; Accessible lacks complete supported-task evidence; Maintainable has successful builds and useful separation but unresolved error/reporting and duplicated operation concerns. This is a gap view, not a signed gate register or release decision.

**Achieved assurance:** strong for specific gaps in the inspected implementation and claims; broader governance operation remains unknown. **Material UNKNOWNs:** adoption decision, accountable current gate/decision records, actual data-flow/retention coverage, external obligations, backup erasure and cross-project contracts. Missing supplied records are not proof that records do not exist elsewhere.

## 5. Findings

Concern bands describe the pathway's consequence, not measured probability or an aggregate score. HIGH maps here to S3 serious (core-task loss, possible irreversible user work or sensitive-history ownership consequences); MODERATE maps to S2 moderate. No S4/S5 catastrophe is established. Likelihood in ordinary use is UNKNOWN. Repeated fixtures establish reproducibility only under their named conditions. Candidate vault and partial-result consequences are not promoted merely because severity is high.

| ID | Finding | Band | State |
| --- | --- | --- | --- |
| F-01 | Files entry crashes the native audit build | HIGH | CONFIRMED in audited UI configuration |
| F-02 | Replace can destroy the existing destination on copy failure | HIGH | CONFIRMED |
| F-03 | Mirror treats a missing source root as an empty folder | HIGH | CONFIRMED |
| F-04 | Sync deletes the old target before validating a replacement | HIGH | CONFIRMED |
| F-05 | Mirror labels different bytes Identical when metadata matches | MODERATE | CONFIRMED |
| F-06 | Secure deletion follows a selected file symlink | HIGH | CONFIRMED |
| F-07 | MP3 title edits discard existing metadata frames | MODERATE | CONFIRMED |
| F-08 | Vault automation reaches beyond vaults managed by Nautica | HIGH | CANDIDATE consequence; source behavior established |
| F-09 | Vault health and Repair labels exceed the checks performed | MODERATE | CONFIRMED claim mismatch |
| F-10 | Graph history has no user-facing export and deliberate erasure lifecycle | HIGH | CONFIRMED target gap |
| F-11 | Protection wording overstates current capability | MODERATE | CONFIRMED wording gap |
| F-12 | Several utility paths suppress errors or incomplete results | MODERATE | CANDIDATE end-to-end impact; source behavior established |
| F-13 | Git badges miss filenames requiring porcelain quoting | MODERATE | CONFIRMED |
| F-14 | Large-directory enumeration is a substantial bottleneck | MODERATE | CONFIRMED component latency; full UI criterion unresolved |
| F-15 | Keyboard commands compete for the same bindings | MODERATE | CONFIRMED source collision; runtime dispatch unresolved |
| F-16 | Cancellation semantics conflict with the draft contract | MODERATE | CONFIRMED source/intent mismatch |
| F-17 | Search silently limits results to 500 | MODERATE | CONFIRMED source limit; UX impact untested |

### F-01 — Files entry crashes the native audit build

**Type / state / scope:** Concern; CONFIRMED in audited UI configuration. Domains U03/U04/U05/U06/U11; C09. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Draft F-001/F-002/F-011; target Graceful Degradation. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** U-003/U-004/U-006; U-005; S GraphApplicationShell; [GraphWorkspace.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Views/Graph/GraphWorkspace.swift:58).

**Observation:** Selecting Files terminated the isolated Debug app twice. Both macOS reports record EXC_BAD_ACCESS/SIGBUS on the main thread with SwiftUI StackLayout frames. The isolated Release app also terminated; its report has the same exception and SwiftUI StackLayout failure pattern.

**Counter-evidence:** Onboarding, Objects, Collections, PAF import and Settings operated. The crash is not evidence that all services fail. **Material UNKNOWNs:** Root cause UNKNOWN. Original bundle identity, other OS/toolchain combinations and ordinary distribution launch were not tested.

**Cause / confidence:** UNKNOWN. Crash frames identify the failing layout path, not the source defect. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Isolate the GraphApplicationShell/BrowserView layout and window configuration interaction; retain the crash fixtures and repair the Files entry before relying on downstream browser flows.

**Verification:** Reproduce entry, navigation, selection and file operations with isolated stores in the supported Debug and Release configurations; then verify the ordinary bundle identity with controlled data. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-02 — Replace can destroy the existing destination on copy failure

**Type / state / scope:** Risk; CONFIRMED. Domains U04/U05/U08/U11; C01/C09. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Draft F-011 preservation intent; target Preservation Over Perfection / Reliability and Data Integrity. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-004 replace_missing_source; [FileOperationService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FileOperationService.swift:297).

**Observation:** With an existing synthetic destination and a source that disappeared, .replace removed the destination and returned a failed copy. The old bytes were gone. Removal precedes coordinated staging/publish. The same pre-removal branch serves move.

**Counter-evidence:** Ordinary copy uses private staging, no-follow copying and exclusive publish; its control succeeded. **Material UNKNOWNs:** Move failure, disk-full, crash and permission-revocation variants were not dynamically exercised.

**Cause / confidence:** Established contributing branch: destination removal precedes incoming-item staging and validation. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Selected batch, folder or affected target; links can extend beyond selection. Original bytes may require an independent backup; the probe established no service rollback. Often after the attempted action; no preflight assurance demonstrated. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Stage and validate the incoming item before replacing; keep the old item recoverable until publish and record rollback outcome. Do the replacement inside the coordinated transaction.

**Verification:** Repeat disappeared-source, denied-read, disk-full and cancellation scenarios with a pre-existing target; original target must remain recoverable on failed publish. Related: F-04/F-16. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-03 — Mirror treats a missing source root as an empty folder

**Type / state / scope:** Risk; CONFIRMED. Domains U04/U05/U06; C01/C09. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** SyncMode mirror claim; target safe failure and work preservation. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-004 mirror_missing_left; [FolderSyncService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FolderSyncService.swift:115).

**Observation:** An absent left root produced deleteRight for important.txt. Executing the plan permanently removed the right-side sentinel. Missing-root scanning skips enumeration instead of failing the comparison.

**Counter-evidence:** A delete plan is expected for a genuinely empty, readable source; the defect is failure to distinguish empty from unavailable. **Material UNKNOWNs:** Permission-denied and partially unreadable trees were not dynamically exercised. UI confirmation cannot make an invalid plan accurate.

**Cause / confidence:** Established contributing branch: a nonexistent root returns an empty scan. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Selected batch, folder or affected target; links can extend beyond selection. Original bytes may require an independent backup; the probe established no service rollback. Often after the attempted action; no preflight assurance demonstrated. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Require both roots to exist, be directories and scan successfully; make any traversal failure block destructive planning. Revalidate root identity before execution.

**Verification:** Prove missing, disconnected and denied roots never produce or execute deletions; a readable empty root must remain a separate explicit case. Related: F-04/F-05. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-04 — Sync deletes the old target before validating a replacement

**Type / state / scope:** Risk; CONFIRMED. Domains U04/U05/U11; C01/C09. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Target Reliability and Data Integrity; sync update intent. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-004 sync_source_disappears; [FolderSyncService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FolderSyncService.swift:257).

**Observation:** After comparison proposed copyToRight, removing the source caused execution to remove the destination and then fail copying. No recovery record or Trash move restores the old target.

**Counter-evidence:** The service reports the thrown copy error; it does not conceal that exception. **Material UNKNOWNs:** Mid-copy interruption and cancellation recovery remain untested.

**Cause / confidence:** Established contributing sequence: remove destination, then copy the possibly stale source. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Selected batch, folder or affected target; links can extend beyond selection. Original bytes may require an independent backup; the probe established no service rollback. Often after the attempted action; no preflight assurance demonstrated. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Use the shared staged replacement engine; revalidate each plan entry and preserve displaced targets until completion. Offer a recoverable delete policy for mirror.

**Verification:** Change or remove a source after preview and interrupt publication; verify old targets and completed/incomplete results precisely. Related: F-02/F-03/F-05. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-05 — Mirror labels different bytes Identical when metadata matches

**Type / state / scope:** Concern; CONFIRMED. Domains U02/U04; C06/C10. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** SyncMode exact-clone wording; target meaningful save states. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-004 mirror_equal_metadata_different_bytes; [FolderSyncService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FolderSyncService.swift:179).

**Observation:** AAAA and BBBB with equal sizes and matching modification times were classified Identical and skipped. Metadata equivalence does not establish byte equivalence.

**Counter-evidence:** Size/time comparison is a useful fast mode; it can be acceptable if labeled as that mode rather than verified identity. **Material UNKNOWNs:** Extended attributes, package contents and filesystem timestamp precision were not evaluated.

**Cause / confidence:** Established comparison policy: size and modification time are treated as identity. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Rename the fast state to metadata match; add an explicit content-verified mode and define which attributes a mirror preserves.

**Verification:** A content-verified mirror must detect same-size/time different-content fixtures. Keep the fast-mode limitation visible. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-06 — Secure deletion follows a selected file symlink

**Type / state / scope:** Risk; CONFIRMED. Domains U04/U08; C01/C02/C07. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Selected-item authority; target Human First / purpose-scoped access. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-004 secure_delete_file_symlink; [SecureFileDeletionService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/SecureFileDeletionService.swift:174).

**Observation:** Deleting a file link opened its target with O_RDWR, truncated the target to zero bytes and removed the link. The target lay outside the selection. A directory-link probe failed safely and retained its child.

**Counter-evidence:** The confirmation sheet warns that deletion is irreversible and includes an SSD notice. Directory-link traversal was not established by the probe. **Material UNKNOWNs:** Hard-link aliases, snapshots, SSD remnants, short writes and interruption are not exhaustively verified.

**Cause / confidence:** Established contributing mechanism: the file open follows symlinks before truncation. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Selected batch, folder or affected target; links can extend beyond selection. Original bytes may require an independent backup; the probe established no service rollback. Often after the attempted action; no preflight assurance demonstrated. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Reject links and special files by default; inspect inode/type without following links, use O_NOFOLLOW and verify the opened inode. Define hard-link policy. Retire erasure guarantees not supported by the storage medium.

**Verification:** File and directory links, hard links and replaced-inode races must preserve unselected targets. Separately validate honest erasure wording; no forensic-erasure assurance is granted. Related: F-11. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-07 — MP3 title edits discard existing metadata frames

**Type / state / scope:** Concern; CONFIRMED. Domains U04/U05; C06/C10. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** MetadataEditorService lossless claim; target unknown-field preservation. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-006 mp3_title_edit; [MetadataEditorService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/MetadataEditorService.swift:200).

**Observation:** A synthetic MP3 header containing an artist TPE1 frame lost that frame after a title-only edit. TIT2 was added and the synthetic audio payload remained. The writer rebuilds selected frames rather than merging the old tag.

**Counter-evidence:** The replacement is staged; the probe did not show loss of audio payload. **Material UNKNOWNs:** Real codec playback, cover art, ID3 versions and image/PDF/M4A fidelity remain unverified.

**Cause / confidence:** Established contributing mechanism: ID3 reconstruction drops untouched frames. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Original bytes may require an independent backup; the probe established no service rollback. Often after the attempted action; no preflight assurance demonstrated. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Use a format-aware merge that preserves untouched and unfamiliar fields; expose unsupported formats and back up before rewriting.

**Verification:** Edit one field in representative real media and verify untouched metadata, artwork, audio bytes and playback; the synthetic frame-loss regression must pass. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-08 — Vault automation reaches beyond vaults managed by Nautica

**Type / state / scope:** Risk; CANDIDATE consequence; source behavior established. Domains U05/U08/U13; C02/C07/C09. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Target explicit revocable delegation / scoped access. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S VaultService / VaultAutomationService; screenshot 11; [VaultAutomationService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/VaultAutomationService.swift:124).

**Observation:** Monitoring starts at application launch. It discovers mounted images system-wide, uses app-local inactivity, and lockAllVaults attempts to detach all recognized images with -force. Sparsebundle recognition checks structure rather than encryption; mount fallback uses volume name.

**Counter-evidence:** Auto-lock switches and timeout are visible; no vault was mounted in the observed Settings state. **Material UNKNOWNs:** No real vault was created, locked or detached. Actual unrelated-volume impact and OS blocking behavior are UNKNOWN. Additional source anchors: [system-wide image discovery](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/VaultService.swift:339), [forced detach](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/VaultService.swift:242).

**Cause / confidence:** Source establishes system-wide discovery and forced detach; actual unintended-detach consequence remains UNKNOWN. Strong for source behavior; consequence remains candidate. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Maintain an explicit registry of user-authorized managed vaults and exact image/device identity. Default to graceful detach, surface busy/failed locks, and make force an explicit decision. Use defined system-idle semantics.

**Verification:** With disposable images, prove unrelated and unencrypted images are excluded, same-name volumes never substitute, busy volumes report failure and successful lock really removes the authorized mount. Related: F-09/F-11. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-09 — Vault health and Repair labels exceed the checks performed

**Type / state / scope:** Concern; CONFIRMED claim mismatch. Domains U02/U04/U06; C06/C16. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Target Evidence for Product Claims / meaningful save states. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S VaultDiagnosticsService / VaultService; [VaultDiagnosticsService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/VaultDiagnosticsService.swift:191).

**Observation:** Repair invokes hdiutil verify and returns output without checking exit status. Health relies on structural checks, encryption metadata and mountability, yet describes band integrity as optimal and hardware AES/APFS. Mountability alone cannot establish all those claims. lockVault also ignores process failure status.

**Counter-evidence:** Structural checks and diagnostic logs provide useful limited evidence. Verify can diagnose supported image formats. **Material UNKNOWNs:** Corrupt-image, busy-volume, repair and post-repair fixtures were not executed.

**Cause / confidence:** Established reporting mismatch: verification is labeled repair; process status and narrower checks do not support all claimed properties. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Name this Check Image and report only tested properties. Implement real repair separately with recovery preparation and explicit exit/postcondition checks.

**Verification:** Feed corrupt and unsupported fixtures; failed verification must not report repair success or proven encryption/integrity. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-10 — Graph history has no user-facing export and deliberate erasure lifecycle

**Type / state / scope:** Concern; CONFIRMED target gap. Domains U12/U13; C02/C15/C17. Concern band HIGH; severity S3 serious.

**Basis and expected condition:** Target User Ownership / Privacy and Context Minimization / Information and Affected-Person Review. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S GraphStore / GraphWorkspace / Settings; E-007; [GraphStore.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/GraphStore.swift:21).

**Observation:** Objects, Relationships, evidence, packages and audits are retained in append-only records. Archive hides an Object; it does not erase historical payloads. PAF exports a selected audit context, but the inspected API/UI has no general graph/settings portability, selective erasure or retention controls.

**Counter-evidence:** Append-only records, hashes and time snapshots support provenance. Deleting a View leaves Objects intact, as documented and tested. **Material UNKNOWNs:** No supplied adoption decision establishes r3 as prior Nautica policy. External backup/restore deletion handling and migration recoverability are UNKNOWN.

**Cause / confidence:** Established design gap: immutable history has no inspected user-facing selective retention/erasure or general export lifecycle. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Separate verifiable history from sensitive payload retention; design usable versioned export, retention and deliberate deletion that also addresses evidence blobs, backups and restoration. Preserve appropriate non-sensitive deletion receipts.

**Verification:** Round-trip supported data/settings; erase a selected subject and verify payloads and future restores obey that deletion. Define shared-copy limitations. Related: F-08/F-11. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-11 — Protection wording overstates current capability

**Type / state / scope:** Concern; CONFIRMED wording gap. Domains U01/U02/U06/U08; C02. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Draft privacy intent; target Evidence for Product Claims. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** Screenshots 01/02; S secure-delete sheet; X-02; [SecureDeleteConfirmationSheet.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Views/Chrome/SecureDeleteConfirmationSheet.swift:128).

**Observation:** Onboarding says no cloud and files never leave the Mac while the product includes cloud folders, network connection and external sharing surfaces. Secure-delete wording calls overwrite cryptographic shredding and implies physical flushing, though return values are ignored and modern SSD erasure is not established.

**Counter-evidence:** The SSD notice acknowledges retained remnants. No telemetry client was found in the source search; actual network silence was not measured. **Material UNKNOWNs:** Provider-triggered networking, external copies and forensic erasure are UNKNOWN. No claim of a confirmed telemetry leak is made.

**Cause / confidence:** Established wording gap. Complete network behavior and physical remanence remain UNKNOWN. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** State local-first operation and explicit external actions accurately. Call overwrite best-effort logical overwrite, disclose snapshots/copies and promote protection before data is written.

**Verification:** Review all interface and documentation claims against named evidence and limits; verify chosen provider/network scenarios before asserting no network traffic. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-12 — Several utility paths suppress errors or incomplete results

**Type / state / scope:** Concern; CANDIDATE end-to-end impact; source behavior established. Domains U04/U05/U06; C06/C16. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Target visible degradation / preserve known-good data. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S ArchiveService / QuickActionService / TagService / MetadataEditorService; [ArchiveService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/ArchiveService.swift:234).

**Observation:** Encrypted-DMG staging silently ignores copy errors and duplicate basenames. PDF combining skips unreadable inputs if any pages succeed. Native tag writes and M4A replacement errors are suppressed. These paths can return a successful artifact or stale display without a per-item account.

**Counter-evidence:** FileOperationResult already models per-item transfer success/failure; that pattern can be reused. **Material UNKNOWNs:** Archive, PDF, read-only tag and M4A failure cases were not executed end to end.

**Cause / confidence:** Source establishes suppressed errors; actual misleading-success end-to-end outcomes remain UNKNOWN. Strong for source behavior; consequence remains candidate. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Use explicit per-input results, conflict-safe staging and publish only after completeness checks or an acknowledged partial result. Keep source files unchanged on failure.

**Verification:** Probe duplicate basenames, unreadable inputs, denied attributes and unsupported media; every omitted or failed input must be visible. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-13 — Git badges miss filenames requiring porcelain quoting

**Type / state / scope:** Concern; CONFIRMED. Domains U04/U06; C10. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** GitService status-resolution claim; target usable truthful information. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-007 git_spaced_filename_mapped; [GitService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/GitService.swift:111).

**Observation:** An untracked file with spaces produced quoted map keys; lookup by the real filename failed. Line splitting and raw quote handling also create risks for newline/rename names and basename fallback.

**Counter-evidence:** Regular filenames have source-present mapping and stage commands use argument arrays. **Material UNKNOWNs:** Commit/checkout/discard, unusual Unicode names and pipe pressure were not tested.

**Cause / confidence:** Established mechanism: quoted status paths are retained as literal key characters. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Parse a stable NUL-delimited porcelain format and key by exact repository path; avoid ambiguous basename fallback.

**Verification:** Space, Unicode, quote, newline and rename fixtures must map to their exact file; unrelated same-basename files must not inherit badges. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-14 — Large-directory enumeration is a substantial bottleneck

**Type / state / scope:** Concern; CONFIRMED component latency; full UI criterion unresolved. Domains U10/U11. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Draft AC-F001-02 and performance intent. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** R-007 listing/sort; [FileSystemService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FileSystemService.swift:24).

**Observation:** The optimized service harness returned all 15,000 synthetic items in 5,260, 6,139 and 5,374 ms. In-memory name sorting of 50,000 items took 37 ms. The service produces its complete array before returning.

**Counter-evidence:** Sort was fast in this fixture. Measurements are current-run evidence, not historical validation claims. **Material UNKNOWNs:** End-to-end render, 60 fps scrolling, cold OS caches, calibrated machine load, peak memory and Quick Look latency were not measured.

**Cause / confidence:** Slow complete enumeration established. Per-item cost attribution remains UNKNOWN pending profiling. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Profile per-item resource reads/provider detection; load essential fields first, return chunks and defer expensive metadata. Define a repeatable supported-machine benchmark.

**Verification:** Measure actual first useful paint, scrolling, sort, preview and cancellation on the named PRD fixtures. Service-only results cannot certify the UI threshold. Related: F-01/F-17. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-15 — Keyboard commands compete for the same bindings

**Type / state / scope:** Concern; CONFIRMED source collision; runtime dispatch unresolved. Domains U06/U07; C04/C05. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Draft keyboard-centric intent; target stable configurable interfaces. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S NauticaApp commands; observed duplicate View menus; [NauticaApp.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/NauticaApp.swift:152).

**Observation:** Cmd-1 through Cmd-4 are assigned to both view modes and tab selection (tabs use Cmd-1 through Cmd-9); Cmd-Shift-D is used for dual pane and Desktop; Cmd-Option-R is used for batch rename and inspector Recents. Two View menus were visible.

**Counter-evidence:** The product exposes many operations through menus and offers density settings. **Material UNKNOWNs:** Which action wins in every focus/window state is UNKNOWN because Files entry blocked the keyboard walkthrough.

**Cause / confidence:** Established duplicate declarations. Runtime dispatch outcome remains UNKNOWN. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Create one action/shortcut registry with conflict checking, configurable bindings and a searchable command chooser. Consolidate the View menu.

**Verification:** Verify dispatch in each relevant focus state and preserve keyboard-only access to complete core tasks; check VoiceOver separately. Related: F-01. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-16 — Cancellation semantics conflict with the draft contract

**Type / state / scope:** Concern; CONFIRMED source/intent mismatch. Domains U02/U04/U13; C09. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Draft AC-F011-02; FileOperationService cancellation contract. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S FileOperationService; R-003 single-item cancellation tests; [FileOperationService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/FileOperationService.swift:41).

**Observation:** The draft requires the destination return to its pre-operation state. The implementation removes the in-flight staging copy but leaves previously completed batch items; its comment explicitly describes that behavior.

**Counter-evidence:** Single-file and recursive in-flight cleanup tests passed. Keeping completed work may be the preferable deliberate product policy. **Material UNKNOWNs:** Multi-item cancellation and cleanup timing were not dynamically measured. The PRD remains Draft, with no approved amendment established.

**Cause / confidence:** Established specification/implementation disagreement; preferred policy needs a product decision. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Choose and approve a clear batch-cancel policy; if retaining completed items, label and account for them and provide appropriate recovery. Do not silently rewrite the specification to match code.

**Verification:** Class C: resolve the material intent/implementation conflict. Class A: verify the approved semantics, multi-item outcomes and the stated cleanup target. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### F-17 — Search silently limits results to 500

**Type / state / scope:** Concern; CONFIRMED source limit; UX impact untested. Domains U04/U06/U10; C06. Concern band MODERATE; severity S2 moderate.

**Basis and expected condition:** Search completeness expectations; target visible degradation. Intended task outcomes and any protection/identity claims should match what the named operation establishes; target criteria apply as a gap lens. **Evidence:** S SearchService harvestResults / ScopeBarView; [SearchService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/SearchService.swift:182).

**Observation:** Harvesting reads only min(resultCount,500). The inspected scope UI receives results.count rather than total query count and contains no truncation warning. Results beyond the first 500 are omitted.

**Counter-evidence:** The cap bounds memory/work. In-folder filtering remains a separate source-present option. **Material UNKNOWNs:** A Spotlight-indexed 501+ result fixture was not executed; search ordering and scope behavior remain unverified.

**Cause / confidence:** Established harvesting cap and absence of inspected total/truncation state. Strong for stated observation; qualified by listed material UNKNOWNs. **Risk context:** Named subsystem and its records/workflows; ecosystem-wide effect not established. Depends on corrective design or saved state; not verified. Visible from the stated runtime/source/wording evidence; end-to-end detection may vary. Exposure is feature use; population/frequency are unmeasured.

**Recommendation:** Show returned/total counts and a visible limit, with pagination or an explicit request for more; preserve local scope and explain unindexed/offline paths.

**Verification:** A broad indexed query must distinguish no matches, incomplete index, gathering and truncated results. Related: See cross-domain synthesis. No remediation or risk acceptance occurred; this remains the frozen observation.

### Additional investigation notes, not confirmed exploit findings

Encrypted ZIP creation supplies `-P` with the password in process arguments; encrypted tar uses a CBC/PBKDF2 pipeline without an inspected authenticated envelope. These are source-grounded credential/integrity concerns. Archive traversal exploitation, process disclosure on this OS and round-trip integrity were not tested; do not describe Zip Slip or secret theft as confirmed. Review authentication and extraction boundaries before making protection claims. See [Services/ArchiveService.swift](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/frozen/source/Nautica/Services/ArchiveService.swift:1).

Vault Keychain helpers save a device-local item and use a separate LocalAuthentication check; a stored `userPresence` access-control constraint was not found in the inspected save path. This does not establish access by another app or an OS ACL bypass. Make the selected threat model, credential-access policy and usable fallback explicit, then test them with disposable secrets. Apple documents user-presence constraints as a platform option. [Apple Security reference](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence).

A complete NSFileCoordinator guarantee is not established across sync, secure deletion and helper mutations. Apple supplies read/write coordination APIs; wrapping calls alone would not repair pre-deletion order, stale plans or authority checks. [Apple Foundation reference](https://developer.apple.com/documentation/foundation/nsfilecoordinator). Provider operations, metadata rewrites, Git subprocess bounds and the one-shot embedded shell deserve focused verification rather than blanket capability claims.

### Cross-domain synthesis

1. **Preservation and coordination:** ordinary staged copy is undermined by pre-deletion in replacement and an independent sync implementation. A shared operation engine could carry consistent identity checks, staging, postconditions, cancellation and recovery across both; coordination is one part of that design.
2. **Provenance and privacy:** immutable history aids auditability, but retained personal payloads need correction, deliberate deletion and expiry. Operation receipts should record only the information needed for recovery and traceability, with usable controls; “append-only” cannot stand in for ownership.
3. **Automation and agency:** sleep/idle locking is convenient only when it identifies authorized vaults exactly and reports incomplete detach. App inactivity, a system image list and a volume-name fallback combine into a larger boundary concern than any one alone.
4. **Performance and information quality:** fast comparisons, search caps and deferred metadata can be legitimate optimizations when their limitations remain visible. Metadata match cannot become verified identity; limited results cannot become complete search.
5. **Power and discoverability:** Files, Objects and PAF need stable entry points and adjustable detail. Complex expert capability can stay discoverable through a workspace choice and action registry; an unexplained empty graph should not be the sole starting assumption.
6. **Local hosting and external evaluation:** PAF accurately exposes its manual boundary. Context exported for another evaluator still needs exact input selection, sensitive-data review and disclosed contamination limits. Package hashes support byte integrity without granting authority or proving publisher authenticity.

## 6. Required verification

These checks explain what is needed to evaluate the named existing intent/target or close a finding. They do not authorize repairs or convert recommendations into adopted product requirements. Classes A evaluate selected criteria; B applies when correction/closure is claimed; C resolves actual conflicts. No special independent verifier or job title is imposed.

| Check | Class | Why needed / what it resolves |
| --- | --- | --- |
| V-01 Files entry and principal browser tasks | A; B for F-01 closure | Draft core F001/F002/F011 and target degradation: controlled Debug/Release and ordinary bundle launch; then navigation, selection, preview and operations. |
| V-02 Failed replacement and stale-plan sync | A; B F-02/F-04 | Preservation intent and target reliability: disappeared/denied sources, interrupted publication and old-target recovery; precise completed/incomplete accounting. |
| V-03 Mirror root validity and identity | A; B F-03/F-05 | Mirror task and claim accuracy: missing/denied/disconnected roots cannot cause valid deletion plans; distinguish metadata and verified content. |
| V-04 Selected-item deletion authority | A; B F-06 | Target Human First/scoped access: file links, directories, inode replacement and hard-link policy must preserve unauthorized targets. |
| V-05 Media field preservation | A; B F-07 | Editor lossless claim / target unknown-field preservation: single-field real-format edits retain untouched supported information or disclose conversion limits. |
| V-06 Vault scope, authentication, busy lock and diagnostics | A; B F-09; candidate evaluation F-08 | Selected protection/automation claims and target controls require exact authorized identity, real detach outcome and honest health results; disposable images/secrets only. |
| V-07 Graph portability, retention and restore deletion | A target; B F-10 | Target ownership/privacy: exported supported records/settings are usable; deliberate erasure/expiry governs payloads, evidence and restoration. Adoption changes do not erase current gap. |
| V-08 Real UI performance and accommodated tasks | A | Draft latency/fps targets and target accessibility: supported-machine paint/scroll/preview, keyboard-only and chosen native accommodations. Service timings are insufficient. |
| V-09 Exact current package lifecycle | A | P-1 product capability: an authoritative compatible package must complete review/freeze/export/capture/index. Current kit blockers must remain explicit; no local fabrication to force success. |
| V-10 Cancellation policy conflict | C, then A/B F-16 as applicable | Draft says restore pre-operation state; implementation retains completed items. Resolve intended semantics explicitly before calling either test suite or implementation definitive. |
| V-11 Updated product scope and security criteria | C, then A | Draft no-network/no-vault-Keychain scope conflicts with expanded working copy. Establish the current approved scope/criteria without silently changing the historical draft. |
| V-12 Partial results, Git paths, shortcut dispatch and search limits | A; B for respective confirmed findings | Current task/capability claims need truthful partial outcomes, exact file identity, deterministic commands and visible query limits. Evaluate candidate F-12 with controlled failures. |

Failed legacy tests also need reconciliation with the intended current API. Current Custom Pattern success is counter-evidence, not permission to delete inconvenient tests. A failed dangling-link naming expectation can be repaired while retaining no-overwrite safety. Any defect correction should preserve this audit's original fixtures and evidence; later effective closure records are separate dated states.

Recommended sequence: repair the Files blocker and demonstrated destructive paths; consolidate consequential operation semantics and truthful outcomes; resolve scope/cancellation intent; add retention/portability and vault authorization boundaries; complete the affected performance/accessibility/recovery checks; then pilot new concepts. This is prioritization advice, not approval to implement or release.

## 7. Optional additional corroboration

Class D options include a second reviewer of narrow already-established outcomes, broader comparative usability studies, fuzzing beyond selected requirement cases, longer resource profiling, additional optional assurance and prototype research for new ideas. They remain optional and do not create an unmet criterion, gate closure or lower a determination merely because they are absent. Required native accessibility or product recovery evidence listed above remains Class A rather than being mislabeled optional.

Eight alternatives and ten concepts are developed in [ALTERNATIVES-AND-IDEAS.md](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/ALTERNATIVES-AND-IDEAS.md), with benefits, tradeoffs, feasibility and cheap evaluation. “Novel” means proposed for this inspected Nautica baseline; no worldwide originality or patent search is claimed. These proposals are advisory until deliberately adopted.

## 8. Material evidence or authority conflicts

| Conflict / discrepancy | Disposition |
| --- | --- |
| Draft cancellation restores the pre-operation state; code retains completed batch items | Material product-intent conflict: Class C V-10. Draft status preserved; neither silently wins. |
| Draft zero-network/restricted-Keychain scope; current provider/share/vault capability | Material current-scope conflict: Class C V-11. User audit inclusion does not itself approve a new PRD. |
| Legacy sequence tests versus current format default | API/test expectation discrepancy: explicit Custom Pattern succeeds. Resolve intended compatibility; no blanket rename failure verdict. |
| Draft assumes third-party Finder batch rename | Current official Finder documentation corrects the factual premise. No unresolved authority conflict; revise competitive rationale in a later baseline. |
| Kit prose says regression excluded; archive contains regression-related files | Package inventory discrepancy. Those contents are not used as audit answers; names/hashes only. No claim of clean blinded context. |
| Kit sidecar references absent entry points; separate TXT initiation exists | Readiness gap, not Class C authority conflict. Human audit can use supplied framework/TXT with disclosure; product correctly blocks kit freeze. |
| Historical validation versus new current observations | Different states, fixtures and dates are not interchangeable. Historical results are excluded; new failures establish only the selected freeze. |

## 9. Historical/current-state treatment

This response describes October 7's frozen working copy and current run. Earlier validation material seen during intake is not admissible proof for current conclusions. No September 30 answer, other-version package or prior test result is imported as a current pass. Historical records retain their original dates and conditions; this audit neither retroactively erases them nor certifies them.

No product remediation occurred. All 143 selected original files still match the freeze at final verification. Audit deliverables are new records under docs/audits; original sources, user content and preexisting dirty work remain outside audit mutation. Later correction, adopted criteria or re-audit should reference these IDs and create a separate dated state.

## 10. Limitations

The live core Files evaluation is incomplete because of reproducible crashes. The instrumented audit bundles use disposable Foundation storage and separate identifiers, but differ from a distribution bundle in launcher/identity/signature bytes. Text-section equality is a narrower check; ordinary bundle identity, notarization, packaging and other macOS/hardware combinations were not tested. SwiftUI crash frames do not establish a source root cause.

One post-crash controller relaunch omitted the disposable home and exposed personal graph labels. That state was rejected and the process stopped before personal operations; a wrapper then enforced the home. Native picker incidental labels were excluded. No intentional personal-file mutation/export occurred, but perfect isolation throughout the run is not claimed. The initial inherited-preference screen is also rejected.

Service harnesses exercise actual frozen components with named adapters/dependencies and synthetic fixtures. They do not establish full UI integration, real media playback, provider compatibility, archive attack resistance, live vault lifecycle, Touch ID/Keychain enforcement, forensic SSD erasure or complete no-network behavior. The R-004 directory-link probe failed safely; no recursive external-tree deletion claim is made. Probe setup was corrected to canonical paths and to catch a directory enumeration exception; only the recorded final run supports findings.

The 15k timing is complete service enumeration in three runs, not first useful paint, frame rate or calibrated cold-cache performance. The 50k result is in-memory sort, not full UI sort. No resource-limit target is certified from those measurements.

VoiceOver, accommodated complete workflows, large text, measured contrast, reduced motion and user studies remain unperformed. Legal/contractual applicability and adoption/operating records are not established by supplied evidence. No comprehensive vulnerability-advisory, supply-chain or license clearance was performed. Official competitor descriptions are documentary comparisons, not hands-on competitive tests or performance claims.

The legacy package's absent Markdown entry points and source archive constrain readiness and publisher provenance. Sixty matching present hashes do not authenticate the publisher. Same-conversation intake exposed some historical material, so this is not a perfectly clean-context or independent blind evaluation. The current user-directed audit and blocked product package lifecycle remain distinct.

The output is a completed audit report of executed coverage, findings, limits and advice. It is not a complete product acceptance test, implementation, closure verification, approved r3 adoption, release authorization or assurance certification. Absence of supplied evidence is not proof of non-occurrence.

AUDITOR RESPONSE FROZEN
