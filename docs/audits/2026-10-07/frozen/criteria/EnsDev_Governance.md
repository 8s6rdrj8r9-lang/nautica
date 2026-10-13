# EnsDev Governance v1.7

Defines how EnsDev's governing documents relate, which one wins in a conflict, and how any of them is changed. This is the authoritative home for document relationships and governance procedures. Indexes may identify files without redefining those relationships.

## Document Stack

Authority flows top to bottom. When operational obligations conflict, the higher governing tier wins. The Manifesto frames purpose and is not an operational command; rhetorical purpose cannot override a constitutional invariant or resolve an engineering gate. Code is the least authoritative artifact in the system.

1. **Manifesto** — purpose. *Why EnsDev exists.* Rhetorical by design; holds no operational rules.
2. **Constitution** — invariants. Non-negotiable commitments that define EnsDev's identity. Rarely amended.
3. **Doctrine** — application stance. The opinionated bets on *how* we build to honour the Constitution.
4. **Engineering Handbook** — enforcement. Concrete rules and the checks that verify them.
5. **Spec** — what a given product does this cycle.
6. **Tests** — evidence about whether the spec holds within the conditions checked.
7. **Code** — the implementation.

**Ontology** supplies shared vocabulary across tiers. Its limits and temporary mappings are governed by [Ontology Precedence and Temporary Mappings](#ontology-precedence-and-temporary-mappings).

## The One-Home Rule

Every governing rule has one authoritative home. Other documents reference it rather than establish competing copies. Doctrine supplies implementation stances and the Handbook supplies concrete verification; those are applications of higher commitments, not permission to alter them. Indexes, decision summaries and generated reading copies identify their source and cannot override it. If a rule already exists elsewhere, link to it. Historical changelog entries describe past versions, not current requirements.

## Amendment Rule

Changes are versioned per document. Each document carries its own dated `## Changelog`. Filenames are stable and carry no version — the version lives in the heading and the changelog, so an amendment never renames a file or breaks a reference.

- **Major (x.0)** — changes to constitutional commitments, document authority, or tier responsibilities. Record the rationale and downstream impact. A substantive incompatible replacement may conservatively use a major version to flag migration.
- **Minor (x.y)** — compatible clarifications and additions within an existing tier, including deduplication or wording.

Both require a dated changelog entry and a downstream impact check recorded in a governance decision record, covering affected documents, products, tests, and exchange formats. Regenerate the source manifest and index after amendment. Apply the existing authority to approve an amendment; a proposed future rule cannot authorize its own adoption.

A version bump without a changelog entry is a defect: the reason for the change becomes tacit knowledge, which the Constitution forbids.

## Scope

EnsDev is currently operated by one person. "We" is structural, not a headcount. This governance is written so it survives that fact changing.

## Decision Authority and Accountability

The current accountable owner is Arthur George Ens. The owner approves governing amendments and defines who may approve interpretations, releases and scoped exceptions, with records under the procedure below. AI and rule-based automation may perform explicitly delegated work within approved policy; they cannot independently rewrite governance or expand their authority. A product contributor may implement within approved policy but may not silently amend it.

Before delegating authority, record the person or role, permitted decisions, limits, review/expiry conditions, review responsibility, and succession arrangements in the authority register. The initial register is: owner — Arthur George Ens; delegated approvers — none. A delegation or successor appointment requires an owner-approved decision record. If no authorized approver is available, preserve work and pause decisions needing approval; preauthorized work may continue within its bounds. No contributor or model inherits authority by default. These rules continue to apply when headcount changes.

Anyone materially affected, including a non-user, may raise a concern through the product's documented feedback route without an account or payment. Before a product is publicly released, its specification must name an accessible route, the responsible reviewer, and expected acknowledgement/review timeframes, and publish that information; a missing route blocks that release. No promise of an operational route is made by this document alone.

Record the concern, relevant evidence, response, and review outcome without unnecessary personal detail. No retaliation or loss of unrelated product access is permitted for raising a concern. Where another authorized reviewer exists, a challenge to a decision is reviewed by someone other than its maker. In sole-owner operation, record the lack of independent review, reconsider the challenged rationale, and state what evidence would reopen it. Do not present that reconsideration as independent assurance. Respond through the submitting person's chosen supported channel with the decision, reasons, unresolved matters, and how to request reconsideration. Routine quiet logging does not replace that response.

## Interpretations, Disputes, and Exceptions

Identify the relevant source sections and classify the issue as an interpretation, content conflict, unresolved criterion, or proposed amendment. Apply the documented stack before escalating an unresolved issue to the owner. An interpretation cannot introduce a new obligation or erase one; such a change requires an amendment. Record disagreement and reasons, not just the winner.

Constitutional invariants cannot be waived. A lower-tier exception may be approved only where the higher tiers allow it, with bounded scope, justification, alternatives, affected-person analysis, safeguards, evidence requirements, responsible person, and expiry/review trigger. It does not establish general precedent or count as a gate passing. Gate and release effects are defined in the [Handbook](EnsDev_Engineering_Handbook.md#completion-and-release-states).

For an immediate incident, a contributor may stop an unsafe action or contain an ongoing failure using the least harmful reversible measure consistent with higher authority. Record the measure as soon as feasible and submit it for owner review before resuming the affected operation. Emergency containment is not authority for a new release or a permanent policy change.

## Governance Decision Records

Store each decision durably with the project or governance corpus, outside conversation-only memory. Give it an ID and record: question; date; applicable sources and versions; decision type; options and rationale; affected people and conflicting needs; evidence and uncertainties; scope; approver and any delegation; dissent/review outcome; safeguards; expiry or review trigger; downstream changes; and superseded records. Omit irrelevant personal details under the [Constitution privacy invariant](EnsDev_Constitution.md#privacy-and-context-minimization).

An exception, provisional criterion, or temporary mapping carries an explicit expiry or review trigger. Reaching that boundary requires reassessment before renewal; it does not renew silently. An expired or overdue record no longer authorizes new work or release within its scope; preserve existing artifacts and reassess affected states. Review records when their cited authority changes. Keep interpretations distinct from amendments and gate evidence distinct from approvals.

## Competing Legitimate Needs

For a material conflict, identify affected groups and individuals, include non-users where relevant, seek their input where feasible, and document when it cannot be obtained. Assess agency, access, privacy, burden, reversibility, and consequences of each feasible option. Seek separate configurable paths first, then select the least harmful feasible accommodation consistent with the Constitution. Neither headcount nor the label 'edge case' determines priority on its own.

The owner or an explicitly delegated human approver approves the remaining trade-off in a decision record with reasons, residual exclusions, mitigation, and a review trigger. Affected people may challenge it through the accountability procedure. If no option is consistent with the Constitution, block the affected behavior and revise its design rather than waive the invariant. Record the reasoning, alternatives, and residual unmet needs under [Handbook explanations and notifications](EnsDev_Engineering_Handbook.md#explanations-and-notifications), quiet by default with an optional notification control.

## Ontology Precedence and Temporary Mappings

Ontology binds vocabulary; it does not create permissions or override obligations in the governing stack. If a definition would require behavior forbidden by a higher tier, pause the affected interpretation and resolve the definition through an amendment. Do not change the higher rule by relabeling a concept. Purpose rhetoric cannot supply an operational exception.

A product may add explicitly named domain concepts consistent with the shared core, as defined in the Ontology. Product extensions are not silent redefinitions of core concepts. An open mapping or fork is not a settled requirement. To proceed temporarily, record an owner-approved mapping with a unique product/version namespace, the unresolved question, alternatives, scope, interoperability limits, migration plan, and expiry/review trigger. Mark it provisional in schemas and exchange metadata. Do not silently redefine a settled primitive or export an unresolved mapping as the universal standard. Reconciliation requires an Ontology amendment and downstream compatibility review before the mapping is claimed as standard.

## Loader and Corpus Integrity

The legacy filename [ensdev-governance.md](ensdev-governance.md) is retained as a non-normative loader. It is not another governing tier. No personal profile, copied governing prose, default threshold, or independent policy belongs in it. Its index and machine-generated manifest identify the sources; neither can supersede them.

Load all six authoritative source documents in full before making governance-dependent decisions. Report missing, unreadable, or version-mismatched sources and pause only decisions dependent on them. When byte verification is available, check the manifest's SHA-256 values; otherwise state that integrity has not been mechanically verified. Never claim a hash check that was not performed. A manifest mismatch requires reconciliation against the authoritative sources, not blind preference for the manifest.

After any amendment, regenerate the source manifest and validate the loader's index. The source manifest contains source filenames, heading versions, and hashes only. Generated TXT reading copies are non-authoritative, version-labelled renditions of those sources and are regenerated when they change. Distribution packages identify their current corpus and separate it from historical evidence; neither a packaged original nor an older ZIP overrides the current source. Keep task-specific personal context separate, purpose-bound, and governed by the Constitution and Handbook. A loader cannot override an assistant platform's instruction hierarchy.

## Sole-Owner Continuity and Bounded Pause

The current continuity arrangement is bounded pause. No backup approver or successor is appointed by this amendment. The owner retains decision authority; any future delegation is explicit, limited and revocable under Decision Authority and Accountability.

Each product records how it behaves when the sole authorized approver is unavailable or a required review is delayed. Apply this operation classification:

| Class | Behaviour during absence |
| --- | --- |
| Continue | Previously authorized work within valid scope and safeguards may continue. Ordinary user functions need not stop merely because a governance approver is absent. |
| Pause | New decisions needing approval, expanded authority, unresolved consent changes, and work relying on expired/overdue permission remain paused. |
| Contain | Ongoing failures use the existing emergency-containment authority and documented least-harmful measures. Preserve recoverable work; containment does not grant release or amendment authority. |
| Queue and respond | Record approval requests and concerns for review. Use the product's stated response expectations and supported channels to acknowledge receipt and communicate known delays, without inventing a return date or claiming an independent review. |

At an exception or review deadline, identify affected new work and ongoing operations separately. Stop initiating work that relies on expired authority. Use the exception/product's defined stop, preservation, safe-completion or containment procedure for in-flight work; the need to reach a safe state is not silent renewal of permission for further actions. Manual user functions and unrelated valid operations remain available where possible.

Record outstanding decisions, affected people, time-sensitive consequences, expiry status and recovery needs with minimal personal context. On return, reassess overdue records and permission coverage before resuming affected paused work. A complaint does not by itself revoke unrelated authorization or make retaliation permissible; material evidence of an ongoing failure still invokes the existing containment process.

The arrangement accepts that approval-dependent decisions and contested reviews may be delayed. It does not represent sole-owner reconsideration as independent review. Review whether bounded pause remains adequate before reliance on multiple public products grows, or when actual delays, material incidents or product criticality show that it is insufficient. Any appointment of a delegate is a separate recorded owner decision.

## PRDs and Coding-AI Work Instructions

Governance sets authority and rules. The PRD occupies the existing product-specification tier: it states the product's required outcomes and measurable acceptance criteria. Technical designs, plans and tasks refine approved requirements without altering them. A coding-AI prompt is a bounded work instruction referencing that baseline; it is not an alternative policy source or a release approval.

The trace is: governing source/section -> PRD requirement ID -> implementation task -> changed artifact -> verification evidence. Evidence can reveal a bad requirement or design, but a failed test or inconvenient implementation does not automatically amend the requirement.

The PRD is the product specification within the existing stack, not a new tier. Technical plans and coding prompts remain subordinate to that specification and the governing sources. Stable requirement IDs connect product outcomes to bounded tasks and verification evidence; routine implementation choices remain within the agent's delegated discretion. Roles and approval handling live here; fields, intake, execution and evidence requirements live in the [Handbook](EnsDev_Engineering_Handbook.md#prd-contract).

PRD states: Draft -> Approved baseline -> Superseded when replaced. An approved version remains an identifiable historical baseline; changes create a new version with recorded approval rather than silently editing the baseline beneath ongoing work. An owner-authorized material change can be recorded during an active task and reflected in the next baseline; no separate ritual approval is required where the authority and decision are already explicit.

The product's authorized approver may approve a separable portion, with unresolved dependencies and scope boundaries recorded. Governance-policy amendments remain with the owner or authority permitted by the governing amendment process. An agent cannot grant itself approval, silently alter scope or infer deployment authorization from PRD acceptance. Approved templates provide structure only; an unfilled template or example is not an approved product baseline.

## Security and Privacy Decisions

Use the existing decision record, authority, competing-needs, exception and release
procedures for material security/privacy trade-offs. Do not create a separate
unaccountable approval path. The product's authorized approver records protection
claims, affected people, alternatives, residual risks, review triggers and unresolved
limits with links to the Handbook design record and verification evidence.

A disclaimer or user toggle does not waive a constitutional commitment or make an
otherwise prohibited disclosure permissible. Offering a less-protected mode requires
a supported product purpose, bounded scope, plain explanation and the applicable
informed authorization. Users cannot authorize disclosure on behalf of others
merely because their information is present in a file.

Review decisions when key custody, recovery authority, recipients, provider access,
information combinations, retention or protection claims change materially. Apply
[Handbook continuing authorization](EnsDev_Engineering_Handbook.md#continuing-authorization-after-change)
without requiring a new prompt for changes already covered by valid authorization.
Product release and exception states remain governed by the existing Handbook gates.
An accepted risk is not evidence that a security control passed.

Security review records identify the reviewer's role, relevant capability, scope,
evidence and limits. When required assurance exceeds available capability, obtain
suitable review or leave the affected gate unresolved. AI consensus is not independent
assurance; no universal external audit or certification is implied.

Incident handling uses the existing emergency-containment authority and sole-owner
continuity arrangement. A named response owner and product-specific communication
plan are required under the Handbook; these do not create an unstaffed 24-hour
service promise or a new delegate.

## Governance Upkeep

1. **Identifiable baselines:** record which governance and PRD versions each product follows. Preserve approval history and distinguish proposals from adopted rules.
2. **Adoption status:** track relevant requirements as implemented, verified, unresolved or covered by a valid exception, using Handbook states. Documentary intent does not establish compliance.
3. **Review responsibility:** assign responsibility and review triggers for consequential decisions, exceptions and unresolved risks. Use scheduled reviews where justified by consequences; existing expiry rules remain controlling.
4. **Change impact:** identify affected products, templates, libraries, schemas, tests and claims when governance changes. Plan adoption without assuming every product needs a rebuild.
5. **Scenario checks:** examine realistic conflicts/failures and edge cases, record contradictions and amendments, and label self-review accurately rather than as independent assurance.
6. **Manageable records:** maintain one authoritative home per rule, linked evidence and clearly retired superseded guidance. Scale documentation to impact and observe privacy/retention limits.

Use the existing owner/authority register and decision procedures. This maintenance
process creates no new delegated authority and no universal review interval.

## External Obligations and Policy Conflicts

Products maintain a proportionate applicability record for operating jurisdictions,
activities, information categories, mandatory external obligations and material
contracts. Record sources, relevant versions/effective dates, applicability rationale,
responsible reviewer and review triggers. The Handbook identifies the product fields.

Distinguish binding requirements from comparative guidance and voluntary standards.
A recommendation does not become mandatory merely because it appears in an audit.
Internal exceptions cannot waive applicable external obligations. This internal
Document Stack does not determine the legal validity or precedence of external duties.

For an apparent conflict, identify the specific obligation and internal provision,
preserve necessary evidence proportionately and pause affected actions where
appropriate. Obtain suitable interpretation where capability or facts are insufficient.
Do not silently waive constitutional commitments, invent legal conclusions, or assume
that internal ownership/permission rules alone settle a legal conflict. Keep unresolved
issues visible while independent valid work continues within its authority.

Record the authorized resolution and necessary changes to product, design, operating
scope or governance using existing amendment/decision procedures. No particular law
is declared applicable to every EnsDev product; scope must be established from facts.

## Changelog

- **v1.7 — 2026-10-04** — Adopts C-01 external-obligation applicability and conflict handling; existing authority and invariants retained. See ../records/GDR-2026-10-04-03.md.

- **v1.6 — 2026-10-04** — Repairs F-01 from ENSDEV-GAP-2026-10-04: restores the Amendment Rule and separates Security and Privacy Decisions / Governance Upkeep headings without changing their substantive controls. See ../records/GDR-2026-10-04-02.md.

- **v1.5 — 2026-10-04** — Adopts security/privacy decision handling and governance upkeep within existing authority. Adopted with the domain walkthrough; see ../records/GDR-2026-10-04-01.md.

- **v1.4 — 2026-10-02** — Adopts the approved PRD and coding-AI document roles, traceability, baseline states and authority boundaries. Existing Spec tier retained; templates remain non-normative. See GDR-2026-10-02-03.

- **v1.3 — 2026-10-02** — Adopts the owner-approved bounded-pause continuity arrangement for C-04, specifying continue/pause/contain/queue behaviour and expiry handling without appointing a delegate. Audit snapshot and verdict remain unchanged.

- **v1.2 — 2026-10-02** — Incorporates approved delegation limits, continuation of preauthorized work, accountable responses, quiet conflict reasoning, amendment/version rules, review-bound temporary decisions and generated-copy handling. Authority stack retained; all seven documents reviewed.

- **v1.1 — 2026-10-01** — Adds authority, accountability, records, exceptions, emergency containment, competing-needs adjudication, Ontology precedence/provisional mappings, and loader integrity procedures. Reviews all six other corpus files for downstream effects.

- **v1.0** — Initial governance layer. Establishes the document stack, the one-home rule, and the amendment rule. Created during the refiling that deduplicated the prior document set and introduced the Doctrine tier.
