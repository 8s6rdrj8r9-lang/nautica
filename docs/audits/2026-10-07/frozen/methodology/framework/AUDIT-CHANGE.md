# Change, Invalidation & Re-audit v0.1

## Principle

A change does not automatically invalidate an entire audit. It
invalidates assurance that depended on what changed.

## Change events

Changes include implementation, design, requirement, dependency,
environment, data, AI, people, governance, scale, exposure, legal
conditions, controls, assumptions, incidents, evidence, and
external-world changes.

Record occurrence and discovery time separately when relevant.

## Impact states

-   `UNAFFECTED`
-   `POTENTIALLY_AFFECTED`
-   `AFFECTED`
-   `INVALIDATED`
-   `UNKNOWN`

Claim/assurance states may include `CURRENT`, `SUSPECT`, `STALE`,
`INVALIDATED`, `REVALIDATION_REQUIRED`, and `SUPERSEDED`.

## Invalidation propagation

Traverse relationships from changed objects to requirements, controls,
evidence, claims, findings, projects, and assurance. Relationship types
should eventually define invalidation semantics.

## Invalidation boundary

Stop propagation only where evidence establishes that downstream
assurance cannot materially be affected. Stable interfaces, isolation
boundaries, controls, or direct revalidation may form boundaries.

## Regression halo

Always inspect a proportionate sample outside the predicted impact
frontier to test whether the dependency model itself is wrong.
Unexpected regressions create both project findings and graph/model
findings.

## Change interaction

Assess all unvalidated changes since the last baseline as a set.
Individually safe changes may interact.

## Assurance debt

Assurance debt is previously established assurance made uncertain by
accumulated relevant change without adequate revalidation. Report
qualitatively with reasons.

## Drift

Support discrete change, gradual drift, incident-triggered invalidation,
periodic review, and external change.

## Baseline

An Assurance Baseline records project state, active profile, evidence
state, verified claims, controls, open findings, accepted risks, and
achieved assurance.

## Re-audit rule

Re-audit the smallest scope that can defensibly restore required
assurance, then establish a new baseline with unresolved limitations
preserved.
