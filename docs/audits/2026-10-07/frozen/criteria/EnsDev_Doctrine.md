# EnsDev Doctrine v2.1

Implementation stances for honouring the [Constitution](EnsDev_Constitution.md). These govern the Engineering Handbook and can evolve through the amendment process.

## Augmentation Over Automation

Users choose what work to delegate. Rules or opt-in AI can carry out defined categories of work within authorized scope; uncertainty grants no extra authority. Prefer designs that make delegation inspectable, correctable, pausable, and revocable, with manual core workflows remaining useful. The permission and irreversible-action checks belong in [Handbook automation controls](EnsDev_Engineering_Handbook.md#ai-and-automation-controls).

## Non-AI Assistance

Provide ontology-based rules and heuristics independently of AI. Basic enabled rules may evaluate local information by default and show suggestions; changes to user records or external actions require the applicable authorization. Users can inspect, disable, and customize individual rules, with advanced editing behind optional detail. A heuristic is a fallible suggestion, not a fact. AI can add interpretation without becoming a prerequisite for core workflows. Explanations use the [Handbook reporting controls](EnsDev_Engineering_Handbook.md#explanations-and-notifications).

## Offline-First

The local experience is a complete core product. Creating, viewing, editing, searching, and organizing locally available data work without a connection where those are product functions. Network services, collaboration, remote information, and cloud AI add capabilities with explicit connection requirements. Sync is optional and scoped by the user.

Prepare for disconnection with downloadable data/resources where relevant and visible offline availability. Preserve offline edits and interrupted work, reconcile duplicates, and surface conflicts without silently discarding work. Unavailable AI can fall back to enabled rules and manual controls. Fallback must stay within the consent boundaries in the Constitution. Distinguish stale, unavailable, and pending information. Concrete verification belongs in the Handbook and product specification.

## Adaptive, Not Amputative Simplicity

Offer adjustable information density with useful defaults for each device and its input methods. Advanced capabilities remain discoverable and revealable. Automatic adaptation is optional, explainable, reversible, and can be locked to a preferred layout. Keep controls and navigation stable during active work.

Device-specific views may offer useful subsets rather than every screen everywhere. State limitations and provide clear handoff or export for work available elsewhere. Within a supported workflow, avoid removing capability merely to make the interface appear simple.

## Build For Edge Cases

Identify specific friction through the end user's account or AI they opt into, supported by observation and testing. The user's correction matters; neither a developer's interpretation nor an inference is unquestionable. Treat the founding perspective as a starting point and actively test assumptions with people whose needs differ.

Consider combinations of accessibility, language, connectivity, hardware, available time, and familiarity. Accommodations do not require diagnosis disclosure or justification. Prioritization considers severity of exclusion, reach, and feasibility; small numbers alone do not make a need unimportant. Record unmet needs and workarounds through the Handbook reporting controls.

## Accommodating Different Needs

Prefer configurable, reversible accommodations and separate paths when legitimate needs conflict. Apply [Governance competing-needs adjudication](EnsDev_Governance.md#competing-legitimate-needs) for residual trade-offs. A majority preference or an 'edge case' label does not automatically settle a conflict.

## Simple Over Clever, Explicit Over Implicit

Prefer clear solutions, familiar patterns, and supported ecosystem tooling when they meet the need. Add abstractions or specialized techniques for demonstrated problems. Keep important dependencies, side effects, assumptions, and reasons understandable to future maintainers. Keep implementation complexity behind the interface rather than assigning it to the user. Explain and maintain complexity justified by performance, accessibility, or other requirements.

## What AI Is For

AI assists with identifying friction, connecting information, discovering dependencies and missing context, and reducing effort in capture, organization, explanation, planning, and authorized actions. Distinguish evidence from inference and make suggestions correctable. Capabilities that specifically require AI are identified; core workflows retain the non-AI assistance and manual paths described above. AI does not independently create consent or governance authority.

## User-Controlled Interoperability

Every EnsDev product provides meaningful data exchange with other EnsDev products and compatible third-party apps using open, documented formats. Users select the receiving apps, information, and one-time or continuous sharing. Use common Ontology meanings with versioned product extensions where needed. Local exchange or file import/export is available where feasible without requiring AI or cloud.

Preserve relevant provenance, detect duplicates, and expose conflicts. Continuous sharing defines how edits and deletions propagate. Disconnection stops future sharing; explain where already transferred copies remain under another app's or recipient's control. Native ecosystem handoff may enhance the experience but is not the only exchange route.

## Ecosystem-Native Design and Tooling

Use each target ecosystem's design, accessibility, navigation, input, and integration conventions, with supported native tooling preferred. Share product semantics and data contracts while adapting interfaces to device roles. Document a departure when a convention itself causes the friction being addressed.

The supported ecosystem roadmap includes Apple, Android, Windows, and Linux with GNOME and KDE Plasma as primary Linux desktop targets. Web/browser access, ChromeOS, spatial devices, and vehicle interfaces are explicit coverage considerations, with applicability decided per product. Ecosystem intent is not proof of implemented support. The [Handbook platform mapping](EnsDev_Engineering_Handbook.md#ecosystem-tooling-defaults) supplies the approved technical defaults and device-view roles.

## Security and Privacy by Design

Design protection around the product's actual information, people and consequences.
Choose privacy-preserving defaults and give each component or recipient only the
access needed for the authorized purpose. User convenience does not justify
unexplained disclosure, excessive collection or a hidden recovery back door.

Prefer supported platform protections, maintained cryptographic implementations
and established protocols over custom security mechanisms. Protection must remain
understandable and usable, including for people with limited devices, connectivity,
memory, trusted contacts or technical familiarity. Recovery and sharing are part
of the protection design, not exceptions to it. State residual risks honestly.

Product-specific protections and choices are recorded and verified through the
[Handbook security and privacy design record](EnsDev_Engineering_Handbook.md#security-and-privacy-design-record).
This stance does not prescribe one encryption architecture for every product.

## Changelog

- **v2.1 — 2026-10-04** — Adds security/privacy design stance; existing invariants unchanged. Adopted with the domain walkthrough; see ../records/GDR-2026-10-04-01.md.

- **v2.0 — 2026-10-02** — Replaces the blanket prohibition on automated judgment with bounded delegation, adds independent non-AI assistance, and incorporates approved offline, adaptation, edge-case, interoperability and ecosystem stances. Major version flags the changed automation stance; tier responsibilities retained.

- **v1.1 — 2026-10-01** — Adds an implementation stance for competing needs, with the decision process retained in Governance.

- **v1.0** — New tier. Collects principles that were previously homeless or misfiled: offline-as-resilience and "power users matter" (formerly operational lines in the Manifesto), "augmentation over automation" (the strategy half), "simple over clever" (formerly inside the Handbook's architecture note), "build for edge cases," and the AI-purpose statement (formerly mislabeled "AI Doctrine" inside the Ontology). Adds the "adaptive, not amputative" principle to resolve the standing tension between the Manifesto's power-user stance and the products' capacity-adaptive density.
