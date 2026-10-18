# Independent final decision: withhold owner watcher production

**WITHHOLD `50d3b1c804b1d5801a54ce6903189229cd8868d6` and dependent stage3 batching.** Retain the existing relevant-source/manifest watcher invalidation behavior. The blocked optimization has real measured-work motivation, but the selected-owner model cannot establish complete invalidation using the current exposed compiler identities. This is a concrete correctness/API blocker, not an open-ended request to optimize or implement a compiler tracking system.

The earlier exact review remains at `exact-50d3-ownerwatch-review.md`: directory-symlink deletion/stat-error and duplicate target selection corrections were accepted, but a cross-owner open-overlay alias path remained. Subsequent independent closed-route validation proves that the proposed per-open-URI footprint correction alone is insufficient.

## Executed closed-route controls

Exact code: `50d3b1c804b1d5801a54ce6903189229cd8868d6` in `/workspace/manuscript-tooling-watch`, based on `3232c8db008fe60804f88bb8a243d15ce8da0a14`. The external overlay adds only one review test; repository production/tests are unchanged by this reviewer. Pinned Go1.25.1 linux/amd64, GOMAXPROCS2, writable shared GOCACHE/GOPATH. No performance measurements were run.

A and B are disjoint sibling directories. A/link.ms is initially a symlink to B/dep.ms. The alias is **never an open document**. Before mutation, each case compiles successfully because project.SourcePath applies confinement after EvalSymlinks and the final file is inside B. Cached module names are canonical dep.ms (plus main.ms where applicable).

| Case | Written route selected by B | Before | After replacement + alias watch | Fresh uncached B |
| --- | --- | --- | --- | --- |
| Relative import | B/main.ms imports ../A/link.ms | Success | Same cached Program; success | Failure: path escapes project root |
| Manifest alias | [aliases] @route = ../A/link.ms; main imports @route | Success | Same cached Program; success | Failure: alias target escapes project root |
| Manifest entry | [project] entry = ../A/link.ms | Success | Same cached Program; success | Failure: entry path escapes project root |

Every case ran twice: with only B open, and with an independent ordinary A/main.ms open/cached. All **six controls confirm the stale/fresh disagreement**. Thus ignoring outside-all-owner events is not the only issue: matching the event to A's legitimate owner also fails to identify B's prior resolution dependency.

Mutation removes the symlink and writes a regular A/link.ms, then sends only the URI-only event for that .ms path. It does not edit any open document or configuration text. Event canonicalization now yields A/link.ms, not B/dep.ms. Owner matching evicts no B entry. Fresh B instead encounters the intended confinement error. This is a serial deterministic test, with no sleeps, race timing, unavailable host events, or assumed notification ordering.

The review test intentionally PASSes only when initial success, expected fresh confinement diagnostics, stale cached success and exact Program identity all hold. A PASS is a confirmed baseline-observation defect, not a proposed production regression that accepts the bug forever. The raw run reports all six named subtests and their diagnostics. Test package time was0.034s; a second run retained raw evidence at0.036s. Initial default-cache invocation failed before build because the home cache was read-only; configured runs then passed. No missing subtest/skip or unintended setup error is counted as confirmation.

Artifacts ready for portable research publication:

- `owner-external-alias-control/probe_test.go.txt`: complete external Go test source.
- `owner-external-alias-control/overlay.json`: original executor mapping; publication should regenerate its absolute paths.
- `owner-external-alias-control/repro.log`: all six observed outcomes and final exit evidence.
- `owner-external-alias-control/metadata.json`: exact head, command/environment, pinned tool version, zero tracked working diff, probe SHA256 and relevant watch/project source SHA256 values.

Root and author received these paths. No binaries or generated package-local test files need publication.

## Why per-open footprints cannot establish correctness

A per-open URI→physical-file map can address the earlier open A/link.ms overlay case, including directory aliases beneath A's manifest. It cannot enumerate A/link.ms in these controls: no open URI names that route. Program.Modules exposes only the canonical B/dep.ms endpoint. Original relative Import.Path text survives in syntax, but manifest source/entry/alias values are canonicalized by project.ReadProject; Result.Configuration is raw text, not a complete resolution record. Project.Assignments retains locations, not original parsed path values. Failed resolution and intermediate symlink components also matter to future invalidation.

Reimplementing configuration parsing or guessing relevant original routes inside LSP would create another semantic owner and still require evidence for complete successful/failed route coverage. Selective matching only known canonical modules, canonical roots, actual open URIs, or the currently changed file's nearest project cannot prove the necessary dependency. Changing SourcePath to reject currently accepted lexical-return-inside paths would change language/project behavior and is outside this authorized performance patch.

## Bounded future API direction, without implementation approval

A future coordinated project/frontend/compiler change could expose the filesystem input-route footprint used by each analysis, or an equally conservative upstream signal that selective invalidation is unsafe. The natural owner is the existing resolver while it has original import/configuration/overlay routes and resolution outcomes. LSP should consume that supplied identity rather than infer a second graph from output modules or parse configuration independently.

Any proposal must account for successful and failed lookups, original and physical paths, relevant symlink/manifest topology, configuration source/entry/aliases and cross-owner overlay admission. It should retain bounded path/value metadata with live analyses, release it with the same generation, preserve strict selected-root and rename before/after semantics, and fall back globally whenever completeness is unknown. It need not retain extra Programs, introduce incremental checking, run concurrent checkers or promise atomic filesystem snapshots. This is a direction to evaluate under an explicit cross-package proposal/API review, not an approved implementation or complete API design.

## Scope decision and stop rule

Doing nothing for owner-selective invalidation retains the established global response to the relevant .ms event used by these controls and avoids the demonstrated stale result. There is no claim that all host filesystem events are emitted or that existing watcher filtering handles every directory event. Independent lexical-cache and earlier rename/cancellation work remain accepted; no non-LSP change follows from this hold.

Parent explicitly chose WITHHOLD after receiving these controls. No owner production, optional batching, new input-footprint API, configuration parser or filesystem tracking layer should be published as an implemented remedy in this closeout. Research patches, valid-workload timing and failure controls may be retained as clearly labeled withheld evidence. A later documentation-only exact-head review can verify that separation without shipping the blocked code.
