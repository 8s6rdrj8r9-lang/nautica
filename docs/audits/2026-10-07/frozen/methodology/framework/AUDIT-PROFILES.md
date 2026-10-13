# Audit Profiles, Depth & Assurance v0.1

## Project characterization

Profile project nature, lifecycle, consequence dimensions, scale/reach,
complexity drivers, novelty, change velocity, exposure, sensitive
contexts, authorities, and ecosystem importance.

Projects may have multiple natures. Do not force a hybrid project into
one type.

## Consequence vocabulary

Use `NONE`, `LOW`, `MODERATE`, `HIGH`, `SEVERE`, `CATASTROPHIC`, or
`UNKNOWN` for credible maximum consequence dimensions during profiling.

## Audit depth

-   **L1 Triage** --- obvious concerns and escalation needs.
-   **L2 Review** --- structured representative examination.
-   **L3 Standard Audit** --- systematic risk-based audit with
    traceability and cross-domain analysis.
-   **L4 Deep Audit** --- broad coverage, stronger evidence, adversarial
    pass, control verification, specialist escalation.
-   **L5 Assurance / Adversarial** --- actively attempts to invalidate
    important claims; uses independent verification and specialist
    methods where appropriate.

Depth belongs primarily to domains and may also vary by component.

## Assurance

-   A0 no assurance requested
-   A1 indicative
-   A2 reasonable
-   A3 strong
-   A4 high
-   A5 exceptional / specialist-defined

Record both target and achieved assurance. Effort does not guarantee
assurance.

## Profile composition

Reusable profiles and specialist modules compose. When compatible
minimum requirements differ, the stricter applicable requirement
normally wins. Semantically incompatible requirements become explicit
conflicts.

## Escalation

Escalate depth when high-consequence findings, evidence conflicts,
unknown critical dependencies, failed controls, incidents, falsified
assumptions, or systemic concerns appear.

De-escalation requires recorded rationale and appropriate authority.

## Budget

Time, money, compute, people, specialist access, and attention may
constrain performed depth. Record recommended vs performed depth and
resulting assurance limitation. Never relabel shallow work as deep work.

## Progressive auditing

Use L1→L5 escalation where efficient, while allowing consequential
domains to begin deep immediately.
