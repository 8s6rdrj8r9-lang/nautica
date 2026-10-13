# Graph organization, Views, Right Dock, and PAF

## Existing architecture and extension

Nautica originally had filesystem `FileItem`/directory navigation, SwiftData folder display state, GRDB tag associations, and UserDefaults preferences. It had no general entity/relationship store, graph query engine, subsystem registry, or PAF host.

This extension uses the existing GRDB dependency in `Graph.sqlite`, alongside the unchanged tag and SwiftData stores. Objects have stable UUIDs independent of Views and filesystem ownership. Registering the same canonical file URL reuses its graph identity; moving an external file does not automatically update that reference. No directories are recursively indexed or migrated.

Objects and Relationships are append-only revisions, with recorded timestamps. Relationships preserve type, endpoints, source, establishing actor, creation time, origin, status, and optional confidence. Inferred relationships remain labeled and are excluded from traversal by default. Types and metadata are extensible strings and dictionaries.

Views persist explicit object membership, AND filters, and optional bounded traversal. Explicit membership unions with query/traversal results before filters apply. Collection is explicit membership; Smart selects matching Objects; Relationship follows incoming/outgoing/both edges. Mixed definitions are supported. Traversal caps depth at 16 and tracks visited IDs to terminate cycles. Search filters object names, types, and tags; relationship questions can be represented with saved traversal definitions without a new query language.

Deleting a View deletes only its definition and pins. Removing a pin deletes only that pin. Neither operation deletes Objects or source files. Archiving an Object adds a lifecycle revision. Database triggers reject mutation/deletion of graph history and frozen records.

## UI

The application opens to Objects & Views, with the existing file browser accessible through Files. The Right Dock sits within the window content, outside the file inspector, and centers its pins with scrollable overflow. Native buttons provide keyboard focus, Space activation, accessibility labels, and explicit actions; arrow keys move through pins. Labels and compact/expanded layout are preferences. Settings → Right Dock provides View creation, existing View/Object/Subsystem/action pinning, reorder buttons, configuration/rename, and unpinning.

The View builder supports membership, general property filters (including status and numeric/ordinal priority), relationship types, result types, direction, depth, and explicit inclusion of inferred relationships. The Object editor displays relationship provenance. File registration is separate from explicitly capturing evidence bytes.

PAF is registered in `SubsystemRegistry` and accessible from the main navigation and Dock pins. Graph storage has no dependency on a graph renderer. No visual graph explorer is required or included.

## Persistence and migration

`GraphStore` is an actor and creates the `graph-v1` migration lazily:

- `objects`, `relationships`: append-only timestamped revisions, indexed by ID/time/sequence.
- `records`: mutable View, pin, and intake definitions.
- `immutable`: package archives, parsed package records, captured evidence, frozen audit inputs, and frozen responses, each with a SHA-256 digest.

Writes use SQLite transactions. Failures are surfaced in the UI. Existing tag/folder state databases and preferences are not migrated. There is no network service or graph database dependency. Queries currently load the local graph snapshot in memory; larger deployments may later require indexed predicate execution.

## PAF package contract

The loader reads `paf-package.json`, supports package format 1 and the `intake-freeze-clean-audit` interaction model, and requires the declared entry points, templates, framework directory, freeze command, and completion marker. It accepts root or single-directory ZIP layouts and retains the original archive bytes/hash. Identity incorporates archive and supplemental content, so versions coexist without migrating historical audits.

Checksum manifests are validated, and every framework file needs checksum coverage. Missing referenced source archives are recorded separately from framework integrity. SHA-256 verifies bytes against the supplied manifest, not publisher authenticity.

A separate manifest or supplemental files may be imported with a legacy archive, but they cannot overwrite or implicitly rename files. Missing required entry points prevent freezing an audit. The original files remain intact.

The ZIP reader rejects encryption, ZIP64/multivolume archives, links/special files, unsafe/duplicate paths, more than 4,095 entries, entries over 32 MB, and expanded/archive sizes over 128 MB. It reads individual entries into memory through the system unzip tool, verifies CRC/size, and never extracts package paths or executes package scripts.

## Intake, review, and freeze

Intake is a local, user-driven sequence of small groups: objective, governing material, boundary/evidence, limitations, and review. Package intake instructions are available in the flow. Nautica does not include a conversational model runner or automatically infer missing context from documents.

The audited date and recorded graph state date are distinct and visible. Changing the audited date resets the proposed graph date. Objects/relationships absent at the requested graph date cause an error, never substitution with today's graph. A later graph date requires explicit limitations for older propositions. History begins when Nautica records an Object; it cannot reconstruct unrecorded prior states.

The boundary consists of explicitly selected Objects, explicitly selected Relationships whose endpoints are inside that boundary, and explicitly authorized captured evidence. Live source file URLs are stripped. Unauthorized evidence hashes/bytes are excluded. The complete projection metadata, provenance, evidence, dates, exclusions, ambiguities, and external research authorization are reviewed before freeze. Users are responsible for reviewing Object metadata for relevance; selecting an Object includes its metadata.

`FREEZE & START AUDIT` validates that the projection hash still matches the reviewed input, then transactionally stores the projection and new standalone execution context. The private intake transcript stays outside this context. Later evidence/object changes cannot rewrite the frozen input. A separate execution is required for changed inputs.

## Independent execution and output

The supported execution adapter is **manual clean-context export**. Export produces readable methodology files, ISO-8601 projection JSON, authorized evidence bytes, the exact frozen context JSON, and handoff instructions. No model or external service is automatically invoked. External session isolation cannot be guaranteed by this host; the auditor identity and actual boundary limitations must be supplied when capturing a report.

The default format-1 auditor methodology projection includes the start/launch instructions, manifest templates, direct `framework/AUDIT-*.md` files, the specialist module contract, and framework templates. It excludes intake prompts, regression/expected results, validation prompts, patch reports, and arbitrary supplements. Compatible future packages can provide an explicit `auditor_files` list under the framework root; reserved regression/validation/patch material remains rejected. All chosen material is frozen with the input. The complete original package remains in storage, not in the clean auditor export.

The response must end with a standalone `AUDITOR RESPONSE FROZEN` line. Exact UTF-8 report bytes, hash, timestamp, auditor identity, and context declaration become immutable. Audit and Frozen Report graph Objects are created transactionally around this authority artifact. Findings/verification requirements can be indexed only after freeze and with an exact supporting report excerpt. These user-created indices retain report provenance; no conformance or semantic relationship is inferred by a report text parser.

## Validation scope

`GraphStoreTests` covers persistence/reopen, shared identity across Views, non-destructive removal, ordering, filters, traversal, inferred provenance, revisions, file evidence capture, endpoint validation, subsystem registration, and history mutation rejection.

`PAFHostTests` uses clearly identified synthetic fixtures to exercise checksums, incomplete packages, unsafe paths, stale review rejection, explicit freeze, bounded projection, immutable evidence/history, transcript/expected-answer exclusion, export, completion-marker validation, and supported artifact indexing. A separate optional integration test imports a user-supplied real PAF package (`NAUTICA_PAF_PACKAGE`, or the supplied v1.1 Desktop filename when present). Its input remains synthetic; a passing test is not an independent audit.
