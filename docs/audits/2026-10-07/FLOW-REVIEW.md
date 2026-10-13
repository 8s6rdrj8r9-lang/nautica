# Nautica flow review — 2026-10-07

Native screenshots were captured in this run, saved as exact image bytes, reopened and inspected before acceptance. This review uses the isolated audit profile, not the user's ordinary workspace. Step 5 is a named blocker rather than an invented screen.

| Step | Screen / task | General health |
| --- | --- | --- |
| 1 | Welcome | Concern |
| 2 | Permissions | Concern |
| 3 | Favorites | Usable in observed task |
| 4 | Initial Objects workspace | Orientation concern |
| 5 | Open Files | BLOCKED |
| 6 | Create Object | Usable in observed task |
| 7 | Build Collection View | Complexity concern |
| 8 | Open pinned Collection | Usable in observed task |
| 9 | PAF workspace | Clear manual boundary |
| 10 | Import supplied package | Correct blocking behavior |
| 11 | Right Dock settings | Usable in observed task |
| 12 | Security & Vaults settings | Scope concern; behavior untested |


No complete VoiceOver, keyboard-only, contrast measurement, text-scaling or reduced-motion evaluation was performed. Visible text and focus are useful observations, not accessibility conformance evidence. Files-dependent tasks remain incomplete.

## 1. Welcome — Concern

A clear introduction explains the local product and has one primary Continue action. “No Cloud” is too absolute for the implemented provider and network features (F-11).

**Accessibility and limits:** Plain text accompanies icons; screen-reader order and measured contrast are unverified.

![Step 1: Welcome](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/01-onboarding.png)

## 2. Permissions — Concern

Skip for Now allowed onboarding without Full Disk Access. This is a useful permission boundary. “Files never leave your Mac” needs qualification for user-directed sharing and network workflows (F-11).

**Accessibility and limits:** The alternative path is visibly named. Denied-folder recovery, VoiceOver and focus traversal remain unverified.

![Step 2: Permissions](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/02-permissions.png)

## 3. Favorites — Usable in observed task

Common folders are offered with explicit checkboxes and Continue. Selection is understandable; the later sidebar cannot be assessed because Files crashes.

**Accessibility and limits:** Checkbox labels are visible. Keyboard-only selection and persistence through permissions changes were not tested.

![Step 3: Favorites](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/03-favorites.png)

## 4. Initial Objects workspace — Orientation concern

A new isolated profile opens an empty Objects workspace with an empty right dock. New file-manager users receive little guidance toward their intended task. Offer Files / Objects / Audits as a first-use choice and remember it.

**Accessibility and limits:** The empty state has a Create Object action. Sparse guidance can burden unfamiliar users; this is an observed orientation risk, not a measured abandonment rate.

![Step 4: Initial Objects workspace](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/04-default-workspace.png)

## 5. Open Files — BLOCKED

Selecting Files terminated two Debug launches and the Release launch. Accepted post-entry screenshots are unavailable because the process exited. U-003/U-004/U-006 establish the blocker (F-01). Downstream navigation, selection, menus, previews and operations were not accepted as live UX evidence.

**Accessibility and limits:** This blocks a core task for every input method in the audited configuration. No broader accessibility verdict follows.

**Blocker evidence:** [U-003-files-crash-first.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-003-files-crash-first.ips), [U-004-files-crash-repeat.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-004-files-crash-repeat.ips), [U-006-files-crash-release.ips](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/U-006-files-crash-release.ips).

## 6. Create Object — Usable in observed task

A synthetic AuditFixture Object was created through the form. Type, tags, status, priority, notes and lifecycle are discoverable. The form exposes many fields at once; optional detail could reduce first-use workload without removing fields.

**Accessibility and limits:** A focused field is visible. Required-field announcements, invalid input, keyboard submission and large-text behavior remain unverified.

![Step 6: Create Object](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/05-new-object.png)

## 7. Build Collection View — Complexity concern

AuditCollection was created by selecting explicit membership and pinning it. The explanation that Views do not own Objects helps. Rules and relationship-scope controls remain visible for a simple Collection; show type-relevant controls first with optional detail.

**Accessibility and limits:** Labels help distinguish functions. Long forms, focus order, relation traversal and VoiceOver were not tested.

![Step 7: Build Collection View](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/06-view-builder.png)

## 8. Open pinned Collection — Usable in observed task

The dock pin opened the Collection and showed its one synthetic Object. This links configured navigation to a visible outcome. Preserve names in compact modes and explain that removing a pin does not delete content.

**Accessibility and limits:** A visible focus state was captured. Focus transfer into results and compact-label alternatives remain unverified.

![Step 8: Open pinned Collection](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/07-pinned-collection.png)

## 9. PAF workspace — Clear manual boundary

The screen explicitly says no model runner is installed and explains external evaluation. This is honest capability disclosure. Import, review, freeze, export and capture should remain clearly distinguished from running an evaluator.

**Accessibility and limits:** Readable empty states and named actions are present. A complete keyboard/assistive-technology audit lifecycle was not performed.

![Step 9: PAF workspace](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/08-paf-workspace.png)

## 10. Import supplied package — Correct blocking behavior

The original legacy kit plus sidecar was imported without content rewriting. Two absent Markdown entry points are listed and Freeze is blocked. Sixty packaged hashes were verified. Hash integrity does not authenticate the publisher.

**Accessibility and limits:** Text identifies the blockers rather than relying only on color. Navigating directly to missing-file remedies and error announcements remains unverified.

![Step 10: Import supplied package](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/09-package-blockers.png)

## 11. Right Dock settings — Usable in observed task

Density and labels can be changed; pin types and reordering/removal are explicit. Help explains the consequence of removing a pin. The observed expanded mode supports discovery, while defaults need better first-use guidance.

**Accessibility and limits:** Textual choices are visible. Keyboard reordering, focus after removal and compact modes with VoiceOver are unverified.

![Step 11: Right Dock settings](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/10-dock-settings.png)

## 12. Security & Vaults settings — Scope concern; behavior untested

Auto-lock on sleep and screen lock were on; inactivity was 15 minutes; mounted count was zero. The settings expose automation but do not establish which images are authorized. Scope, busy volumes and actual locking remain untested (F-08/F-09).

**Accessibility and limits:** Switch labels and timeout text are visible. Timeout meanings, announcements and accommodating users who need longer sessions need explicit verification.

![Step 12: Security & Vaults settings](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/screenshots/11-vault-settings.png)

## Evidence handling

`01-start-objects.png` inherited earlier preferences and is rejected as default-state evidence. After one crash, the UI controller relaunched without the disposable home and exposed personal graph labels. That state was rejected and terminated before personal operations; the launcher was then changed to enforce the disposable home. Incidental native file-picker labels were excluded. Accepted evidence is limited to the numbered screens above; perfect isolation throughout the run is not claimed.

The product source was unchanged. The audit apps use separate bundle IDs, a disposable Foundation home and a native launch wrapper. Ad hoc re-signing changed signature bytes; the product executable text section hashes matched the built originals. Ordinary distribution launch is not demonstrated. See [UI-ISOLATION.json](/Users/arthur/Development/Nautica/docs/audits/2026-10-07/evidence/UI-ISOLATION.json).

AUDITOR RESPONSE FROZEN
