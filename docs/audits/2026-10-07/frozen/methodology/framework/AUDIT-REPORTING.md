# Audit Reporting & Views v0.1

## Principle

The canonical object is audit state. Reports are views generated from
that state.

Views may omit detail but may not distort meaning. Unknown remains
visible. Important summary statements retain traceability.

## Core views

-   Executive
-   Project Owner
-   Remediation
-   Assurance
-   Claim / Assurance Argument
-   Findings
-   Finding Detail
-   Evidence
-   Provenance
-   Domain
-   Controls
-   Assumptions
-   Change Impact
-   Baseline Comparison
-   Audit Comparison
-   Trend
-   Ecosystem
-   Specialist
-   Incident
-   Decision
-   Unknowns
-   Coverage
-   Exclusions

## Executive view

Show purpose, scope, mode, completion, baseline, target vs achieved
assurance, consequential findings, evidence gaps, accepted risks,
revalidation requirements, major limitations, and decisions required.

Do not publish an overall project-health percentage.

## Unknowns view

Explicitly surface critical unknowns, evidence gaps, indeterminate
claims, unknown likelihoods, unverified controls, unexamined domains,
specialist review, missing access, and evidence conflicts.

## Redaction

Redaction is a view operation over canonical audit state. Do not create
a sanitized alternate truth. Where permitted, disclose that restricted
consequential findings exist even when their details cannot be shown.

## Historical reports

Issued reports are versioned snapshots referencing audit state,
baseline/project state, view/filter/redaction policy, and generation
time.

## Machine-readable future

v0.1 Markdown is authoritative while ontology evolves. A later
structured graph/state may generate Markdown and UI views. Avoid
premature schema lock-in.

## Accessibility

Do not rely on color alone. Use explicit labels and semantics for
severity, state, and assurance.
