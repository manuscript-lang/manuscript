# Independent skeptical review: editor snapshot and scheduling proposal

Reviewed proposal `snapshot-proposal.md` against main
`a988705cbd5ed9c7424ac891aa42893c2805474a` in
`/workspace/manuscript-tooling-fixes`. Read AGENTS.md, manuscript-change,
tooling/compiler/simplify/taste skills, relevant compiler/language/tooling and
repository experts, architecture/editor contracts, and current analysis,
frontend selection, project overlays, server, transport, workspace and rename
paths. This review edits no production or test files and runs no benchmarks or
heavy tests. Existing extension modification and toolchain entry belong to
other work and were left untouched.

**Decision: the proposal survives in the narrower concrete form below.**
Implementation may proceed with these constraints. A generalized graph-subset
cache, retention of every workspace selected-root graph, or asynchronous checker
workers are not approved by this review. Exact-head implementation review and
behavior/heap/race evidence are still required before publication.

## Material concerns that must shape implementation

1. **Module selection replaces the entry; it does not add an extra root.**
   `pkg/frontend/modules.go:26` assigns `config.Entry = options.Module` before
   visiting it. Application `analyze` first checks the default manifest entry,
   then only when Program is nonnil and requested module is absent does it check
   the selected module (`pkg/tooling/lsp/analysis.go:43`–`:49`). A fallback graph
   must not overwrite the cached default entry graph or supply diagnostics for
   another requested module merely because that graph happens to contain it.

   Example: entry imports good.ms; unreachable.ms imports bad.ms. Opening
   unreachable.ms must get its selected closure and diagnostics, while the entry
   must retain its original closure. If the default result has Program==nil,
   current analyze returns its diagnostics without trying a selected root; a
   new unconditional fallback would change error scope and conceal manifest or
   entry failures. Preserve that branch exactly, including when malformed
   recovery yields a nonnil but incomplete Program.

2. **Graph membership is insufficient for strict workspace selection reuse.**
   workspaceAnalysis uses AnalyzeOnly=true, Module=current file, Recover=false
   (`workspace.go:64`). A default recovering graph cannot replace it. Even two
   strict library selections can behave differently on bad source: a selected
   entry's visit failure clears graph.Modules and returns early
   (`frontend/modules.go:41`–`:47`), whereas failure during later discovered
   module visits appends diagnostics while retaining neighboring modules
   (`:50`–`:65`). The fact that libraries normally discover all source/test
   files does not prove equivalent failure behavior or diagnostics.

   Require exact selected-root/options identity for workspace/rename cache
   reuse. Do not skip strict checks because a recovering Program contains the
   module. Do not union or filter declarations into an apparently equivalent
   compiler result. Rename must retain every before/after validation and
   capture/collision check in `rename.go:96`–`:150`.

3. **A generation-bounded cache can still introduce quadratic retained heap.**
   Current workspace scanning processes one selected-root graph at a time.
   Session-caching one distinct closure per discovered file can retain O(N²)
   Program data on a chain/dense import graph, including when no files are open;
   it creates a new regression rather than fixing the ten-open-tab duplication.
   Keep session ownership limited to the default/fallback snapshots needed by
   live open documents. Workspace selected-root graphs remain transient, or use
   explicitly bounded eviction. A per-request map of every before and after
   rename graph can have the same peak-memory problem; do not retain all of them
   together just because they will be released after the request. Retain only
   what is demonstrably reused and measure peak as well as post-GC heap.

4. **Canonical identity must not change nearest-manifest lookup or overlay
   validation.** FindManifest currently uses the requested path spelling before
   module canonicalization (`analysis.go:35`); malformed nested manifests stop
   lookup. Resolving a document's symlink first can select a different nearest
   manifest or alias set. Keep that order. Canonicalizing an existing manifest
   for a cache key is reasonable only after its selection. New unsaved files
   have no full EvalSymlinks result: project.SourcePath owns confined parent
   resolution, dangling-link rejection and overlay eligibility (`paths.go:63`).
   Do not treat an EvalSymlinks failure as permission to collapse arbitrary
   paths. Conservatively miss the cache when identity is not established.
   Preserve CanonicalOverlay conflict detection for two URIs/symlinks carrying
   different text; dedup must not pick one snapshot silently. Nested projects,
   aliases and root confinement remain delegated to project/frontend.

5. **Scheduling bounds describe waiting, not total latency.** A 25ms budget
   cannot bound diagnostics completion while a whole compiler check is
   nonpreemptible. Timer/select scheduling also adds lifecycle and starvation
   states unnecessary for the measured queued bursts. Prefer the smaller
   consecutive-queued-change batching algorithm below. If a timer is later
   necessary, it must keep docs/cache mutation serial and require explicit
   close/EOF/shutdown tests and a single owned timer, without claims of a hard
   25ms response deadline.

## Accepted concrete implementation boundary

### Session analysis

One serial server owns the current documents and a cache owner for that exact
overlay generation. Every accepted open/change/close and relevant watched-file
event replaces/drops the generation's cache state. No cross-generation history,
global *Program map, dependency-diff invalidation or asynchronous checking.

For an ordinary checkedDocument request, retain the existing analyze decision
tree and standard-document guards. Cache the **first default recovering compile**
per selected nearest manifest for this generation. Reuse that same default
result for another open document only when it represents that document's first
attempt; return it directly when Program is nil or module membership succeeds.
When Program is nonnil and membership fails, cache a separate selected-root
recovering result under the manifest plus requested canonical module identity.
Never promote a selected fallback to default, and never reuse one fallback for
another module based on containment. Standalone files retain separate roots.

All inputs influencing checking must match: recovery/mode/selected-root flags,
all open overlays, and watched disk state. It is simplest to enforce generation
immutability rather than hash every input. The cache path applies only when d
is exactly the document in that generation; private or caller-supplied modified
documents must use uncached analysis. ScopeMarker completion snapshots and its
up-to-24 repaired analyses are explicitly isolated, including changes to other
open documents in its private copy. Do not cache them in the live generation.

A snapshot may lazily own its source occurrence index and LintProgram result.
Store those adjacent to the owner/result, then let URI aliases point at that
owner; a second independent pointer-keyed map is unnecessary unless a caller
needs it. Do not key all nil Programs to one shared error result. Keep line/doc
indices bounded by source length. Index entries can retain checker identities
because the owner already retains the same Program; never put them in a global
standard cache. Only immutable standard lexical/header text may be global.

Shared lint must preserve current graph-level suppression: LintProgram returns
no advisories when that graph has diagnostics. Bucket its existing findings by
module, but do not run it on a different graph or make it report advisories
previously suppressed by the requested closure's errors. Publish diagnostics in
the existing URI/position order with the accepted document version.

### Workspace work

Deduplicate filesystem walks for equal selected discovery roots/modes before
reading files, with deterministic ordering. Do not assume parent-root coverage
automatically subsumes nested manifests or standalone directory rules.
workspaceDocuments' includeNested behavior and hidden/vendor/node_modules/
symlink exclusions stay intact. Keep every previously searched unopened module.
Deduplicate locations only after preserving checked binding identity.

Strict per-file checks stay selected-root based and transient. Bounded
per-request reuse is acceptable for repeated **exact** selections; using open
recovering snapshots as strict workspace substitutes is not. Rename before and
after belong to different overlay generations even within one request; no
source index or check result may cross that boundary. Keep returned edit URI,
document version and original source offsets unchanged.

### Mutation batching

The smallest acceptable scheduler is serial, bounded batching of consecutive
already-queued didChange notifications. Apply each change's ordered range edits
and monotonic version guard to docs, invalidating generation state as usual,
but defer publish until queue empties, a small count/time budget is exhausted,
or the next non-change frame becomes the ordering boundary. Flush before that
boundary's feature processing and on lifecycle/shutdown/EOF. Do not wait for a
new frame when the queue is empty, reorder requests, or skip edit application.
Treat didOpen/didClose as explicit boundaries initially; expanding their
coalescing can be measured separately. Preserve immediate empty diagnostics on
close and never republish a pending stale URI/version after close or reopen.

Invalid/stale notifications do not dirty the state, clear legitimate pending
dirty work or create a new generation. An invalid range must keep the whole
notification transactional, matching current didChange's local-copy behavior.
The final accepted version must be published, including a nonempty diagnostic
when deliberately invalid; coalescing obsolete versions is the intended change.
A bounded count is sufficient for starvation control in this queue-only design;
do not introduce a wall-clock debounce dependency into tests.

### Cancellation

Check pending cancellation before expensive dispatch, then between workspace
discovery files, selected-root analyses and expensive indexing phases. Keep the
existing final check to close races. Return RequestCancelled for canceled
requests and release/avoid partial request-level aggregates. A completed compiler
result is not partial, but do not install an incomplete graph/index or publish a
partial workspace symbol/reference/rename result as successful.

Keep the 32-frame bounded queue and admit that unread cancellation behind a
full queue cannot yet be observed. One whole compiler check remains
nonpreemptible. No unbounded reader-side pending-frame list, concurrent checker
worker or pervasive compiler context changes belong in this patch. CPU work
saved for already-read cancellations and checks between workspace files are
meaningful improvements with those limits.

## Do-nothing and smaller alternatives

Doing nothing is safe but keeps directly measured duplicate check/heap work,
obsolete diagnostics bursts and canceled workspace request blocking. It is not
the best choice given user-approved performance work and concrete evidence.

Local index/header/position/docs improvements alone offer large gains at very
low semantic risk and should remain separable/reviewable. They do not address
open-tab graph/heap multiplication or ten-edit diagnostic bursts. Debounce alone
addresses bursts but not one-edit duplication. A shared default recovering graph
with conservative invalidation plus queue-only batching is the smallest coherent
extension supported by current evidence. Full incremental frontend, graph-union
selection, cross-generation hashes and checker concurrency add substantial
semantic/lifetime risk without a necessary benefit for this patch; reject them.

## Required distinguishing validation

- Count actual compiler calls and assert shared owner/Program identities for
  reachable application modules and libraries. Assert different fallback owner
  identities for distinct unreachable roots. Check no fallback when default
  Program is nil. Add an erroneous unreachable file and verify no new default
  entry diagnostic, then deliberately introduce an imported type error and
  verify all affected diagnostics update and disappear on reversion.
- Exercise malformed nested manifests, two manifests/alias sets, symlink root
  and file spellings, conflicting duplicate overlays, new unsaved confined
  files, dangling external links, source/test libraries. Reuse must never
  suppress a diagnostic or invent a declaration.
- Preserve private ScopeMarker recovery, standard virtual and exact disk-pinned
  documents, continued stdlib navigation, source implementation identities,
  Unicode/CRLF positions, hover/token/completion nonempty content and output
  equivalence. Tests must establish meaningful payloads, not just zero errors.
- Keep unopened cross-file references and rename behavior, label/type/field/
  interface identities, strict malformed-source rejection and capture checks.
  Explicit strict-root failure tests distinguish a selected entry parse error
  from another discovered module's parse error in a library.
- Queue deterministic edits where the second range depends on the first; stale
  and malformed later edits; invalid latest accepted source; close/reopen,
  shutdown/EOF, more than 32 frames and a bounded long burst. Inspect versioned
  final diagnostics and content. Use barriers or factored batch logic, not
  sleeps as proof of scheduling.
- Cancellation before dispatch must prove no compiler/discovery work occurred;
  cancellation between workspace checks must prove later files did not run.
  No requirement to interrupt one already-running compiler check. Race-check
  transport/server ownership and preserve protocol errors/session shutdown.
- Measure retained and peak heap after repeated workspace requests and rename,
  many open docs and close/invalidate. Memory must not grow by one retained
  selected-root graph per scanned file. Re-run wire workload without concurrent
  heavy load; adapt its observation only for legitimate latest-version
  diagnostic coalescing. Report means/percentiles and sample sizes correctly.

This is an architectural approval with concrete constraints, not an assertion
that an implementation already satisfies them or that proposed speedups have
been measured on the new base. No implementation changes were made here.
