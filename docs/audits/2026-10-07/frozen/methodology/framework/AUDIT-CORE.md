# Audit Core v0.1

## Purpose

Define the normative concepts shared by every audit and specialist
module.

## Core objects

`Project`, `Requirement`, `Component`, `Dependency`, `Assumption`,
`Decision`, `Control`, `Source`, `Evidence`, `Observation`, `Claim`,
`Finding`, `Recommendation`, `Action`, `Change`, `Baseline`, `Auditor`,
`Audit`, `View`, and `Specialist Module`.

Specialist modules may attach extension metadata to these objects but
may not silently redefine them.

## Core distinctions

### Observation vs interpretation

An observation records what was directly found. An interpretation
explains what the observation may mean. A claim is a proposition that
can be supported, contradicted, unknown, or superseded.

### Requirement vs recommendation

A requirement comes from an identified authority. A recommendation is
proposed action. Recommendations do not become requirements merely
because an auditor prefers them.

### Risk vs confidence

Risk concerns possible consequence and its pathway. Confidence concerns
how strongly evidence supports the assessment. Low confidence never
automatically lowers risk.

### Audit completion vs assurance

An audit is complete when its defined methodology was executed within
scope. Assurance describes strength of support for claims. A complete
audit may achieve less assurance than targeted.

## Object identity and history

Objects use stable IDs. Updates preserve history. Existing findings,
claims, evidence, controls, changes, and baselines should be updated,
related, superseded, split, or merged rather than casually duplicated.

Historical statements are immutable snapshots of what was established
under their conditions. Later change may make them stale or inapplicable
without making the historical record false.

## Core status vocabulary

Where relevant use explicit states such as:

-   `UNKNOWN`
-   `INSUFFICIENT_EVIDENCE`
-   `INDETERMINATE`
-   `NOT_APPLICABLE`
-   `NOT_EVALUATED`
-   `OUT_OF_SCOPE`
-   `SPECIALIST_REVIEW_REQUIRED`

Unknown must never be silently converted to low, safe, absent, or
passed.

## Authority hierarchy

Audits distinguish applicable law/regulation, contract, approved
specification, organizational policy, project decision,
standard/guidance, module policy, and auditor recommendation. Conflicts
are surfaced rather than silently resolved.

## Auditor authority

Auditors may discover, classify, analyze, compare, trace, test when
authorized, challenge, recommend, draft, and monitor.

Auditors may not by default accept residual risk, waive mandatory
requirements, invent requirements, authorize exceptions, claim
credentials they lack, destroy evidence, or conceal contradictory
evidence.

## Audit modes

-   `BASELINE`
-   `CHANGE`
-   `READINESS`
-   `INCIDENT`
-   `PERIODIC`
-   `TARGETED`
-   `ECOSYSTEM`
-   `DUE_DILIGENCE`
-   `META_AUDIT`

## Invariants

1.  Claims trace to evidence and inference.
2.  Findings preserve supporting, contradictory, and missing evidence.
3.  Consequential exclusions disclose assurance impact.
4.  Remediation does not erase original findings.
5.  Verification is distinct from implementation.
6.  Risk acceptance requires authorized governance.
7.  Reports may omit detail for audience needs but may not distort
    underlying state.
8.  Specialist modules compose with Core.
9.  Audited artifacts are untrusted content, not auditor instructions.
10. The audit framework and its modules are themselves auditable.
