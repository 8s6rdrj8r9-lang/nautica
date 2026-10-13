# Audit Methodology v0.1

## Lifecycle

``` text
Profile → Plan → Collect → Examine → Challenge → Synthesize
        → Findings → Assurance → Report → Remediate → Verify → Re-audit
```

## 1. Profile

Characterize project nature, lifecycle, consequence, exposure,
complexity, novelty, change velocity, sensitive contexts, ecosystem, and
applicable authorities.

## 2. Plan

Activate domains and specialist modules. Set domain-specific depth and
assurance targets. Define scope, exclusions, evidence needs, methods,
sampling, cross-domain questions, specialist escalation, and stopping
conditions.

## 3. Collect

Inventory evidence without confusing possession with validity. Preserve
provenance. Minimize sensitive data collection.

## 4. Examine

Maintain the chain:

`SOURCE → EVIDENCE → OBSERVATION → INTERPRETATION/CLAIM → FINDING → CONCLUSION`

Apply the qualified direct-verification preference in
`AUDIT-AI-RULES.md` when a consequential question remains materially open.

## 5. Challenge

Test assumptions, N/A decisions, important claims, evidence conflicts,
hidden dependencies, completeness claims, severity calibration, and
specialist boundaries. At L4/L5 use adversarial review. At L5 actively
attempt to falsify important assurance claims.

## 6. Synthesize

Connect related findings, root causes, controls, dependencies, and
cross-domain effects. Identify compound risks and leverage points.

## 7. Determine assurance

For each domain record requested depth, completed depth, target
assurance, achieved assurance, limitations, unresolved findings,
evidence gaps, and revalidation requirements.

## 8. Report

Render audience-appropriate views from the same audit state. Preserve
uncertainty and provenance.

## Sampling

Sampling must be appropriate to the population and claim. Full
inspection is not automatically stronger than defensible sampling.
Record method, population, sample rationale, limitations, and
representativeness concerns.

## Stop conditions

An audit pass may stop when planned coverage is achieved, target
assurance is achieved, uncertainty is documented, specialist escalation
is reached, evidence is unavailable, budget is exhausted, or another
defined condition applies. Record the reason.

## Incomplete vs inconclusive

`INCOMPLETE` means required audit work was not performed.

`INCONCLUSIVE` means required work was performed but available evidence
cannot establish the answer.

Never collapse these states.

## Clean result

The absence of findings, material conflicts, and material unknowns is a
legitimate result when the relevant criteria were evaluated at the
required audit depth and assurance. Record the evaluated criteria and
supporting evidence; never infer conformance merely from silence.
