# Specialist Module Contract v0.1

## Principle

Specialist modules extend the framework. They do not fork it or redefine
Core concepts.

## Module identity

A module defines stable ID, name, version, status, framework
compatibility, and maintainers.

Statuses: `DRAFT`, `EXPERIMENTAL`, `STABLE`, `DEPRECATED`, `RETIRED`.

## Applicability

Modules declare intended subjects, exclusions, and triggers.
Applicability is `NOT_APPLICABLE`, `OPTIONAL`, `RECOMMENDED`, or
`REQUIRED`.

Modules may activate during an audit when new facts emerge.

## Composition and dependencies

Modules may require or recommend other modules. Composition must remain
visible. Compatible minimum requirements combine conservatively.
Semantically incompatible requirements create `MODULE_CONFLICT`.

## Authorities

Classify sources as law, regulation, standard, contractual, industry
guidance, best practice, or module recommendation. Pin versions where
relevant.

## Extensions

Modules may add terminology and extension metadata to Core objects. They
must not create parallel incompatible concepts when Core already
represents the concept.

## Checks

Checks define purpose, applicability, minimum depth, method, expected
evidence, failure modes, controls, and escalation. Check completion is
not proof of complete coverage.

## Evidence and verification

Modules define domain-appropriate evidence requirements and verification
methods by depth/assurance. Destructive methods declare authorization
requirements.

## Controls

Modules may define control patterns. Project controls instantiate them.
Mandatory external controls identify their authority; module
recommendations remain module policy.

## Risk

Modules map specialist consequences into Core risk semantics and may add
specialist dimensions without replacing Core dimensions.

## Stop conditions

Distinguish `AUDIT_STOP`, `OPERATION_STOP_RECOMMENDED`, and externally
authoritative `MANDATORY_STOP`.

## Expertise and credentials

Modules declare capabilities and credentials required by depth. Auditor
profiles are compared against them. AI cannot satisfy
professional-license requirements.

## AI permissions

Declare allowed, conditional, and prohibited AI actions and whether
verification may be AI-performed, AI-assisted, human-required, or
qualified-specialist-required.

## Change rules

Modules may define invalidation rules and drift indicators.

## Assurance criteria

Modules define what A0--A5 require in their specialist context while
preserving Core meanings.

## Validation

Before STABLE, modules should receive internal consistency review, Core
compatibility review, source/authority validation, pilot audit,
false-positive review, coverage-gap review, and AI behavior testing
where applicable.

Modules should support calibration fixtures: known-good, known-bad,
ambiguous, adversarial, and incomplete-evidence cases.

## Minimum contract

A module may contain:

-   identity
-   applicability
-   dependencies
-   authorities
-   terminology
-   domain extensions
-   checks
-   known failure modes
-   evidence requirements
-   verification methods
-   controls
-   risk guidance
-   stop conditions
-   expertise
-   AI permissions
-   depth minimums
-   assurance criteria
-   change invalidation/drift
-   reporting extensions
-   provenance
-   validation status/fixtures

Modules are themselves auditable projects.
