# Independent skeptical review: discovery and owner watcher plan

**Decision: APPROVE stages 1 and 2 for bounded implementation. APPROVE stage 3 only as the separate optional batch step after stages 1/2 correctness checks pass.**

Reviewed the amended `discovery-implementation-plan.md` against `discovery-watch-design.md`, its correctness matrix, and actual `pkg/tooling/lsp` discovery/snapshot/server plus project path/overlay/manifest and frontend selection code. Current isolated checkout is `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`, with no production changes; only its local toolchain symlink is untracked. Compared with the plan's original `c086eed70aeb9eb6d56689d8aca74a9bf0fb4875`, the only LSP difference is the one-line String API fixture spelling correction in `features_test.go`, with no algorithm change. Update the plan's header/base metadata to the actual current checkout.

This is preimplementation design approval, not exact-patch acceptance or proof of performance. Scope remains exclusively `pkg/tooling/lsp`. No tests, builds, benchmarks or production edits were performed by this reviewer.

## Why this survives the do-nothing alternative

Current workspace-symbol discovery deduplicates uncanonicalized root spellings and combines walking with requested-document assembly. Equivalent physical roots can repeat traversal; merely canonicalizing the visited key would omit unopened sources when a symlink root is walked first. Current watcher handling globally evicts all live analyses and republishes all open diagnostics after any relevant event, so an A-only event needlessly rebuilds independent B. These are concrete existing code paths, not a request to invent a new incremental compiler.

Doing nothing preserves that known work and avoids identity risk. The amended plan removes that work at two small boundaries while retaining all compiler checks. It does not cache strict selected Programs across roots, reuse rename before-validation after disk changes, widen import confinement, alter nested-project discovery, add an import-edge graph, or retain workspace compiler identities globally. That bounded benefit justifies proceeding; measured magnitude remains to be established with identical valid workloads.

## Stage 1: approved with the amended assembly contract

Physical discovery identity and selected analysis identity must remain separate:

- Resolve nearest manifest using the lexical request path, including invalid manifests; then canonicalize its containing directory.
- Walk that canonical directory, cache only complete successful disk results for the request, and retain the effective recursive flag.
- Rebase physical relative paths into each lexical selection context before analysis. Preserve each actual URI, text and version independently of the walk's visited state.
- Build the per-physical-file table from all actual ordinary URI records through the existing confined SourcePath contract. An equal-text group can feed generated disk candidates. Divergent admitted text suppresses every generated disk candidate for that physical identity; actual open variants remain.
- Preserve mandatory compiler CanonicalOverlay checks. In particular, distinct-path symlink conflicts remain errors, a CanonicalOverlay failure must never mean “no overlays,” and dangling links must not become newly admitted files.

The original version's vague “avoid assembled-list reuse if ambiguous” was insufficient: a per-caller disk candidate can still manufacture stale conflicts or silently choose a variant without any list reuse. The explicit amended suppression rule resolves that design blocker. It must hold even on the uncached path.

Canonical walk identity does not imply equal diagnostic selection. Maintain ordinary strict per-selected-root analysis, current final-location deduplication, nested-manifest behavior and recursive/nonrecursive policy. New open overlay variants must never be lost because an equivalent physical walk already occurred.

## Stage 2: approved with whole-owner eviction

Whole selected manifest/standalone-directory ownership is a reasonable conservative unit. The plan now supplies the required invariants:

- Capture lexical selection plus lexical/canonical containing roots before compilation, including failures and default/Module shared entries. Nil Program is not absent ownership.
- Use a union of affected old/current/lexical footprints; do not route only to the nearest changed-file manifest or only currently loaded modules.
- Reselect open contexts when topology can drift. Creation/deletion/restoration of nested or ancestor manifests, alias deletion and root retargeting must refresh selection without granting external paths.
- Evict all affected URI/shared entries as one decision. Remove derived Program index/lint state only when no retained live cache entry still owns that Program.
- Preserve B's Program/index/lint identity and diagnostic silence for an ordinary disjoint A event. Immutable virtual/exact pinned disk standard documents have an explicit sentinel, so their intentionally absent workspace owner cannot force every event into global eviction.
- Retain pending diagnostic obligations. A watcher cannot narrow publication scope before prior didChange diagnostics flush; uncached affected open documents remain publication candidates.

The amended immutable sentinel and retained-Program reference scan resolve the other two ambiguities raised during review.

Events representing new/missing files and library/test discovery require root containment rather than loaded-module membership. Parent and nested consumers can both be affected. Explicit hidden/vendor imports remain dependencies despite discovery exclusions. These requirements make the chosen coarse owner unit safer than the superficially smaller edge/filename alternatives.

## Stage 3: approved only in the proposed separate, optional order

The proposed watch-only union is bounded by open URIs, changes invalidation immediately, and defers only diagnostic output. Eligibility is limited to already queued consecutive valid watched-files notifications; requests and all other message classes remain barriers. The 32-frame/25-ms caps add no timer wait for a lone event.

Proceed only after stages 1/2 tests pass, preserve every listed flush barrier (request, close, didChange, error, EOF, shutdown), and keep direct nonbatched handle behavior immediate. Unknown-envelope fallback must union all open URIs, not overwrite an earlier dirty set. When an earlier event already removed A's cache, a later event in the batch must still find uncached open A documents. No mixing watch and didChange batches.

If satisfying these invariants adds a scheduler/state-machine layer beyond the proposed small loop and temporary URI union, omit stage 3. Stages 1/2 are a complete bounded remedy; batching is not required to justify them.

## Safe fallbacks and implementation rejection conditions

Safe fallbacks are explicit and do not block progress:

- Failed directory canonicalization: retain legacy lexical walk/error behavior and do not coalesce uncertain scopes.
- Ambiguous open text: preserve actual URI contexts and suppress generated candidates for that physical identity, while retaining compiler conflict checks.
- Invalid/missing event envelope or individual URI, uncertain local path/topology, or missing live owner metadata: use the existing full invalidation/full publication path.
- Difficult optional batching: omit stage 3.

Reject an implementation that canonicalizes only the visited key, emits canonical disk URIs under a different lexical selection, uses arbitrary overlay map winners, treats validation errors as empty state, ignores ambiguous relevant events, matches only known loaded modules, loses invalid-manifest ownership, or evicts B/its derived facts for an ordinary A event. Likewise reject reuse of compiler results where only physical walks were approved.

## Required evidence before exact-head acceptance

Retain the existing matrix, supplemented by the amended ambiguity/sentinel cases. Assert actual symbols, requested text, diagnostics and preserved object identity rather than nonempty arrays. Compare affected results with fresh uncached analysis after real file/manifest/symlink mutations.

The external physical-walk overlay should count actual traversal/read work for both alias/physical root orders and retain complete symbol/output checks. The A/B watcher experiment must validate refreshed A output and retained B Program/index/lint plus publication behavior before reporting saved work.

The listed deliberate bad alternatives must cause substantive test failures: global watcher invalidation, missing topology handling, canonical-key-only walking and dropped overlay preference. Include divergent encoded URI variants in both query orders, real distinct-path symlink conflicts, ordinary standalone confinement, selected manifest symlink roots, source/test library create/delete, failed manifests, root retargeting, cancellation with a complete next request, and batching barriers if stage 3 lands.

Run affected LSP and relevant race/protocol checks, then arrange independent exact-final-head review. Report memory ownership/lifetime and timing/allocation scope honestly. There is no measured speedup or shipped behavior claim in this design approval.

## Final scope decision

No design blocker remains in the amended plan. This approval authorizes only the bounded implementation and checks above; it does not authorize branch publication or merge. The parent controls integration after exact-head review and CI. The plan's metadata-only base update should be made before implementation for reproducible provenance.

