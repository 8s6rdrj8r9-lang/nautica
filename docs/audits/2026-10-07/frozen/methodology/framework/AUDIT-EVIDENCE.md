# Audit Evidence & Provenance v0.1

## Evidence model

A `Source` is where information originates. `Evidence` is information
admitted for an audit purpose. An `Observation` records what the auditor
directly found. A `Claim` is a proposition evaluated using evidence and
inference.

## Evidence attributes

Record as appropriate:

-   source and provenance;
-   collection date;
-   subject/version;
-   method;
-   directness;
-   freshness;
-   completeness;
-   independence;
-   sensitivity;
-   transformations;
-   limitations;
-   conflicts.

## Evidence states

Useful states include `CURRENT`, `STALE`, `DISPUTED`, `INVALIDATED`, and
`UNKNOWN_APPLICABILITY`.

## Evidence gaps

Missing evidence is first-class. Record what is missing, why it matters,
what claim/domain it limits, and whether it blocks assurance.

### Evidence sufficiency

Evidence is sufficient for a determination when admissible evidence supports
that determination at the strength required by the governing criteria,
applicable project evidence rules, active audit profile and target assurance,
and material provenance requirements, with no unresolved material conflict
that prevents the determination. Evaluate source authority, integrity,
relevance, completeness, and independence as applicable. A signed or
official-looking record does not establish its own authority or sufficiency.

The possible existence of stronger, additional, more direct, or corroborating
evidence does not by itself make supplied evidence insufficient. Require
additional evidence when an existing requirement, material conflict,
provenance defect, missing material fact, or target assurance level makes it
necessary. Do not infer that supplied evidence is sufficient merely because
it has been supplied.

### Material UNKNOWN and evidence-gap gate

Distinguish an unstated fact (absent from the record), a limitation (a
boundary on a supported conclusion), a material evidence gap (missing
evidence needed for a determination), and an audit `UNKNOWN` (an unresolved
material proposition). An unstated or unresolved fact is material only if
resolving it could change an in-scope determination, requirement status,
finding state, or required assurance conclusion. For each material gap or
`UNKNOWN`, identify the determination that could change and why.

An immaterial unstated fact may be recorded as a limitation or observation.
It must not downgrade a supported `PASS` or `FAIL`, add an acceptance
condition, require verification, or become a finding solely because more
information could exist. Preserve genuine material unknowns and their
effect on assurance.

## Contradictory evidence

Do not discard contradictions. Preserve competing evidence and explain
reconciliation or leave the claim indeterminate.

## Independence

Multiple copies, summaries, or AI restatements of one source do not
become independent evidence. Multiple reviewers may provide independent
analysis while still sharing the same underlying evidence.

## Transformations

Derived evidence must retain lineage:

`SOURCE → TRANSFORMATION(S) → DERIVED EVIDENCE → CLAIM`

High-consequence conclusions should be able to return to primary
evidence where practical.

## Evidence minimization

Collect only what is reasonably necessary. Prefer metadata, schema,
samples, redacted excerpts, aggregates, or references when they
establish the claim.

## Secrets

Do not reproduce passwords, tokens, private keys, or similar secrets
unnecessarily. Record exposure without embedding the secret.

## External knowledge

Distinguish project evidence, external evidence, and auditor knowledge.
Time-sensitive external facts require current authoritative sources.

## Completeness language

Use "No instances were found within the inspected scope" unless
exhaustive evidence supports "none exist."
