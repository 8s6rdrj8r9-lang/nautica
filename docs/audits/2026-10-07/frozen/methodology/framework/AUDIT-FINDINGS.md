# Audit Findings & Remediation v0.1

## Finding types

-   Conformance
-   Nonconformance
-   Concern
-   Risk
-   Evidence Gap
-   Opportunity
-   Positive Practice
-   Emergent

A check result is not automatically a finding.

## Finding record

A consequential finding should contain:

-   stable ID;
-   concise statement;
-   type and state;
-   expected condition;
-   observed condition;
-   scope;
-   supporting evidence;
-   contradictory evidence;
-   missing evidence;
-   affected domains/components;
-   risk profile;
-   confidence;
-   root cause status;
-   related findings;
-   recommendations;
-   decisions;
-   remediation;
-   verification;
-   history.

## Lifecycle

Typical states:

`CANDIDATE → CONFIRMED → TRIAGED → PLANNED → REMEDIATING → VERIFYING → CLOSED`

Additional states may include `REJECTED`, `DUPLICATE`, `DEFERRED`,
`ACCEPTED_RISK`, `REOPENED`, and `SUPERSEDED`.

### Candidate to confirmed

Move a finding from `CANDIDATE` to `CONFIRMED` when admissible evidence
sufficiently establishes a deviation from an identified governing
requirement at the required audit assurance. Independent physical
verification is not automatic. Keep the finding as a candidate when the
evidence materially qualifies the observation, contradictory material
evidence remains unresolved, provenance does not support the inference,
the active assurance target requires stronger verification, or the
supplied evidence otherwise fails to establish the deviation. Record
the requirement, evidence, inference, assurance target, and any remaining
material uncertainty supporting the state decision.

## Root cause

Do not force a root cause. `UNKNOWN` is valid. "Human error" is
insufficient without examining enabling conditions. Preserve
contributing factors and systemic causes where supported.

## Relationships

Findings may duplicate, contribute to, compound, depend on, share root
cause with, supersede, or recur from other findings.

## Remediation

Preserve evidence before mutation. Separate discovery, finding
confirmation, remediation authorization, implementation, and
verification.

## Verification

Implementation is not proof of effectiveness. Verification may result
in:

-   `VERIFIED_EFFECTIVE`
-   `PARTIALLY_EFFECTIVE`
-   `INEFFECTIVE`
-   `INCONCLUSIVE`
-   `REGRESSION_INTRODUCED`

Classify recommended verification when the distinction affects a verdict,
finding state, closure, or assurance:

-   **A — Requirement Evaluation:** evidence necessary to determine whether
    an existing governing requirement is met; may affect the verdict.
-   **B — Finding Closure:** verification necessary to demonstrate that a
    confirmed finding has been corrected; may affect closure but does not
    rewrite the historical finding.
-   **C — Material Conflict Resolution:** evidence necessary to resolve
    materially conflicting evidence or authority; may affect the verdict.
-   **D — Optional Assurance:** optional corroboration, robustness testing,
    assurance enhancement, or a proposed new criterion; label it optional.

Class D must not gate a determination, create an unmet criterion or
`UNKNOWN`, or prevent closure when existing closure requirements are met.
Classes A–C must trace to the governing criterion, closure obligation, or
material conflict that makes verification necessary. A recommendation
does not become a requirement through classification.

## Closure

Close only when required action and verification are complete, evidence
is retained, residual risk is assessed, required acceptance exists, and
no blocking related finding prevents closure.

Never erase the original finding or original risk profile.
Preserve the audited state and date separately from later remediation,
verification, closure, approval, or authorized baseline change. A later
correction or approval does not retroactively erase a valid historical
finding.
