# Audit Domains v0.1

## Model

Domains organize audit questions. They do not replace project
characterization, specialist modules, or cross-domain synthesis.

Every audit evaluates all Universal domains, then applicability of
Conditional and Ecosystem domains. A domain may be `REQUIRED`,
`RECOMMENDED`, `OPTIONAL`, `NOT_APPLICABLE`, or `NOT_YET_DETERMINED`.

## Universal domains

The v0.1 universal set is intentionally broad:

-   **U01 Intent & Purpose** --- goals, users, success criteria,
    unintended use.
-   **U02 Requirements & Specification** --- completeness, conflicts,
    authority, testability.
-   **U03 Architecture & Design** --- structure, boundaries, interfaces,
    trade-offs.
-   **U04 Correctness & Fitness** --- whether outcomes match intended
    behavior.
-   **U05 Quality & Robustness** --- edge cases, degradation, defect
    handling.
-   **U06 Human Factors & Usability** --- real human operation,
    workload, error pathways.
-   **U07 Accessibility & Inclusion** --- access needs, alternatives,
    barriers.
-   **U08 Security & Abuse Resistance** --- threats, misuse,
    authorization, integrity.
-   **U09 Maintainability & Operability** --- repairability,
    supportability, knowledge continuity.
-   **U10 Performance & Capacity** --- resource limits, latency,
    throughput, physical capacity.
-   **U11 Testing & Verification** --- verification strategy, coverage,
    validity.
-   **U12 Lifecycle & Sustainability** --- deployment, maintenance,
    migration, retirement.
-   **U13 Governance & Decisions** --- authority, decisions, exceptions,
    accountability.

## Conditional domains

Activate when applicable:

-   **C01 Safety**
-   **C02 Privacy**
-   **C03 Legal / Regulatory / Contractual**
-   **C04 Accessibility Engineering**
-   **C05 Human Factors / Ergonomics**
-   **C06 Data & Information Quality**
-   **C07 AI & Automation**
-   **C08 Ethics / Social Impact**
-   **C09 Reliability / Resilience / Recovery**
-   **C10 Interoperability / Compatibility**
-   **C11 Dependencies / Supply Chain**
-   **C12 Financial / Economic**
-   **C13 Environmental**
-   **C14 Research / Scientific Validity**
-   **C15 Records / Knowledge Management**
-   **C16 Observability**
-   **C17 Provenance / Traceability**

The apparent overlap between universal and conditional domains is
deliberate where a universal concern can require specialist depth. For
example, every human-facing project considers accessibility, while C04
activates when accessibility engineering warrants dedicated evidence and
methods.

## Ecosystem domains

Use for multi-project or shared-system contexts:

-   shared infrastructure and platform dependencies;
-   data/interchange contracts;
-   inherited controls;
-   inherited risk;
-   change propagation;
-   cross-project governance;
-   ecosystem resilience;
-   systemic or correlated failure.

These may be represented as E01--E08 in implementations, but v0.1 does
not freeze names more tightly than the concepts above.

## Cross-domain synthesis

Auditors must inspect interactions rather than treating domains as
sealed boxes. Examples include privacy vs observability, accessibility
vs security, safety vs usability, performance vs reliability, AI vs data
quality, and maintainability vs supply-chain risk.

At L4/L5, a dedicated cross-domain synthesis pass is required.
