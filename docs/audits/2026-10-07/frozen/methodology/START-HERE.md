# PAF v0.1 Auditor Kit — START HERE

This kit is the working distribution for conducting an audit with the validated PAF v0.1 Evidence-Sufficiency Patch.

It contains the complete validated framework payload plus reusable audit-input and report templates. It intentionally excludes the regression fixtures, expected answers, adjudications, and release-validation evidence from the final release package.

## Basic workflow

1. Define the audit request and audited date.
2. Put the governing criteria and admissible project evidence into an auditor-facing package.
3. Assign stable record IDs to supplied evidence.
4. Complete `AUDIT-INPUT-TEMPLATE.md` and, when useful, `EVIDENCE-REGISTER-TEMPLATE.csv`.
5. Start a fresh auditor context.
6. Supply this Auditor Kit and the project-specific auditor-facing package.
7. Use `AUDIT-LAUNCH-PROMPT.md`.
8. Preserve genuine UNKNOWNs where evidence is insufficient.
9. Freeze the completed audit response before any separate adjudication, remediation, or closure phase.
10. If verification is required, collect the missing evidence and run the appropriate verification step without rewriting the original audited state.

## Evidence sufficiency

Under the patched framework, evidence is sufficient when admissible evidence supports the determination at the strength required by the governing criteria, applicable project evidence rules, active audit profile and target assurance, and material provenance requirements, with no unresolved material conflict preventing the determination.

Do not add an independence requirement, special job title, survey method, duplicate test, or other acceptance condition unless the governing material or applicable profile actually requires it.

## Verification purposes

Use the framework's verification taxonomy by purpose:

- **Class A** — verification necessary to evaluate a requirement or resolve a material evidence gap for the requested determination.
- **Class B** — verification necessary to close a finding when the governing closure conditions require it.
- **Class C** — verification necessary to resolve a material evidence or authority conflict.
- **Class D** — optional additional confidence or corroboration; do not silently convert it into a mandatory gate.

Consult the framework files for the controlling normative wording.

## Package boundary

For a real audit, the auditor should receive:

- this kit;
- the audit request/scope;
- governing criteria;
- applicable evidence/provenance/profile rules;
- project evidence; and
- the review boundary and audited date.

Do not include an expected answer, author notes, private adjudication, or material intended to steer the auditor toward a desired result.

## Useful files

- `AUDIT-LAUNCH-PROMPT.md` — reusable fresh-auditor prompt.
- `AUDIT-INPUT-TEMPLATE.md` — project audit-package template.
- `EVIDENCE-REGISTER-TEMPLATE.csv` — structured evidence index.
- `AUDIT-REPORT-TEMPLATE.md` — report skeleton.
- `framework/` — complete validated PAF framework payload.
- `FRAMEWORK-INVENTORY.csv` — exact framework file hashes.
- `SHA256SUMS.txt` — kit integrity manifest.
