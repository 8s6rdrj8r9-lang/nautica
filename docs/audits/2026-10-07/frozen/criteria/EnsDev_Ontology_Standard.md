# EnsDev Ontology Standard v4.0

Shared semantic vocabulary for EnsDev products, data exchange, non-AI rules and AI interpretation. [Governance](EnsDev_Governance.md#ontology-precedence-and-temporary-mappings) defines its authority and provisional-mapping procedure. Shared meanings do not require identical storage types or a database object for every concept.

## Shared Core and Product Extensions

Use common meanings and explicitly named product/domain extensions. Multiple roles are allowed: something identifiable can be an Entity, hold State, and participate in Relationships; an Artifact can also have identity. Product extensions state their namespace, version and mappings without redefining settled core terms.

Identifying a relationship or inferring a state grants no information-access or action authority. Consent, delegation and privacy remain governed by the Constitution and its implementation controls.

## Core Concepts

| Concept | Shared meaning |
| --- | --- |
| Entity | Something identifiable, such as a person, item, place, project, organism or bounded activity. |
| Relationship | A connection between things, such as ownership, membership, sequence or dependency. |
| State | A condition at a particular time or interval. |
| Observation | Something recorded or reported with its source; recording does not establish truth. |
| Artifact | A preserved information object, such as a note, document, profile or plan. |
| Context | A structured description of circumstances relevant to interpretation or action. |
| Action | Something intended, attempted or performed, with those statuses distinguished. |
| Outcome | A resulting condition or effect, distinct from an action merely being marked complete. |
| Learning | A revision to knowledge or a model based on evidence or feedback; a proposed revision is not yet an applied change. |

The legacy grouping into reality (Entity, Relationship, State), information (Observation, Artifact, Context), and agency (Action, Outcome, Learning) is a descriptive aid, not an exclusive class hierarchy. The legacy knowledge ladder—Data, Information, Knowledge, Understanding, Wisdom—is illustrative, not a mandatory progression or an assurance claim.

## Exchange and Evidence Semantics

Carry source, relevant time, uncertainty, and schema/extension version when needed to interpret exchanged information. Distinguish missing, uncertain, disputed, and not applicable; do not collapse them into one value. Preserve appropriate source attribution and correction history while honouring deletion/minimization. Receiving an inference does not convert it into an established fact.

Plans and actual occurrences are distinct. Completion status is distinct from intended or observed outcome. Authorized changes to profiles, rules or workflows are not implied by the presence of an Outcome or Learning proposal.

## Settled Mappings

| Product concept | Shared mapping | Meaning |
| --- | --- | --- |
| Routine | Artifact describing a repeatable plan, with Relationships among its actions | Sequence, timing and conditions belong to the plan; each execution is a separate occurrence. |
| FocusSession | Identifiable Entity representing a bounded activity, with changing State | May be planned, active, paused or ended. Records actions and outcomes; learning is possible rather than assumed. |
| CognitiveProfile | Artifact associated with a person, containing preferences and qualified assessments | The person is distinct from the profile. Temporary capacity is time-bound State; inferred assessments are correctable. |
| Context | Structured description of relevant circumstances | References such as available time, environment or device capability help interpretation without requiring every possible detail. |

These four mappings are approved semantic decisions, replacing the previous open forks. Product schemas still need alignment and verification; approval here is not evidence that current product code has been migrated.

## AuGenda Mapping Guide

This is a documentary mapping guide for product specifications, not an audit of deployed code. Existing type names are anchors for review; storage design remains product-owned.

| Existing product anchor | Ontology interpretation |
| --- | --- |
| InboxItem | Captured Observation; source and uncertainty remain identifiable. |
| Note | Artifact; may remain a note indefinitely. |
| Task | Planned or ongoing Action; completion status is State, not proof of intended outcome. |
| User / Project | Entities; other roles and relationships can coexist. |
| Routine | Uses the settled plan mapping above; execution is separately identifiable. |
| FocusSession | Uses the settled bounded-activity mapping above. |
| CognitiveProfile | Uses the settled Artifact mapping above; capacity assessments are time-qualified. |
| Session result or task effect | Outcome, separate from completion status. |
| Proposed profile adjustment | Learning proposal; application requires the relevant authority. |
| Relevant time, environment and device references | Context, with product-selected representation. |

## Paths Through the Model

The earlier single 'universal lifecycle' is replaced by multiple valid paths:

1. A capture may remain an Observation, become a Note Artifact, or support an Action. It need not become a task.
2. A Routine Artifact may guide a particular execution; that execution records what actually happened separately from the plan.
3. A FocusSession may change State and record actions and Outcomes without producing any Learning.
4. An Outcome may support a proposed revision; evidence, feedback and authorized application determine whether the revision becomes Learning in the stored model.

Observations and AI inferences retain their source, uncertainty and appropriate correction history. No path requires retaining personal information indefinitely. Relationships and provenance obey the same privacy and deletion commitments as the records they connect.

## Changelog

- **v4.0 — 2026-10-02** — Settles Routine, FocusSession, CognitiveProfile and Context; replaces the mandatory-looking lifecycle with multiple paths; distinguishes evidence, plans, outcomes and learning. Major version flags changed mappings for product/schema and exchange review.

- **v3.1 — 2026-10-01** — Clarifies provisional mapping status and references the Governance procedure; all four unresolved questions remain open.

- **v3.0** — Added the ontology→schema mapping table — the change that makes this a Standard. The former "AI Doctrine" section was removed (it was an application stance, not vocabulary) and now lives in Doctrine. Three primitives flagged as open forks; "Context" flagged as mapping to nothing, pending a cut-or-define decision. Refiled per Governance v1.0.
- **v2.0** — Last pre-refiling version (archived).
