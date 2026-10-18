# Independent exact-head review: stage 3

**ACCEPT `d0f2307bda147ad2e68c2e4717ea7b3c6ba98de1`.** No outstanding
correctness or architectural blocker found in the committed production,
documentation and test diff from main `b8c9cc0cf3a436fdaf2b93e6d79516013307a039`.
This accepts the reviewed implementation; integrated checks/CI remain the
parent's publication gate. A later artifact-only commit needs a head refresh
confirming unchanged reviewed source/test/doc blobs.

Reviewed in `/workspace/manuscript-tooling-fixes` at the exact SHA above. Read
the entire 12-file diff, accepted proposal, preliminary concerns, final cache,
server/transport/workspace/rename flows, and new tests. The relevant repository
skills/experts and compiler/project contracts were already loaded for the
proposal and preliminary reviews. Verified no working-tree change to the
reviewed LSP paths/documentation. The untracked `scripts/bench-tooling/` artifact
work is outside this committed review. No production/test edits and no extra
tests or heavy CPU work performed. Committed blob inventory retained in
`stage3-reviewed-blobs.txt`.

## Previous blockers resolved

1. **Standalone/source-root confinement:** compileSnapshot retains an ordinary
   file's requested target identity, rather than resolving a file symlink into
   another standalone root. For a manifest it resolves only the containing
   directory, matching ReadProject; a manifest symlink's destination directory
   does not replace the selected project root. The added order-independent
   standalone and symlinked-manifest tests compare cached versus uncached
   analysis and require opposite success/error states for the distinct roots.

2. **Divergent URI overlays:** canShareOverlays detects distinct live URIs with
   different text mapping to the same decoded filename and disables compile
   sharing for that generation. Per-URI cache results retain the existing
   requested document's overlay precedence. Invalidation clears this decision.
   The encoded-URI regression tests both check orders, requires actual filename
   equivalence, and requires a clean real document plus an erroneous alias.
   Distinct-path symlink conflicts still go through CanonicalOverlay; no new
   preference silently chooses one conflicting snapshot.

3. **Rename cancellation between phases:** checkpoints now follow selected-root
   checking before sourceIndex and follow both strict before/after validation
   checks. Cancellation observed after before checking cannot start the proposed
   source check. TestRenameCancellationAfterBeforeCheck uses an independent disk
   failure control: without the post-check checkpoint the function returns a
   workspace error instead of context.Canceled, so the test distinguishes the
   required boundary rather than only observing a callback counter.

## Cache selection and lifetime assessment

The common analyzeWith function keeps existing standard-document guards,
overlays, nearest-manifest selection, default check and fallback state machine.
Program==nil default results are returned without selecting a new module.
Fallbacks are keyed separately by exact Module selection and never replace the
default graph or satisfy other fallback selections by membership. This preserves
application errors outside entry reachability, selected-root closure semantics,
library source/test discovery and nested-manifest alias isolation.

Only ordinary recovering live documents reach compileSnapshot. Private changed
documents bypass the live URI cache; ScopeMarker/repaired completion and strict
workspace/rename checks keep their prior uncached paths. The cache key omits
options only because this call path fixes those options and invalidation fixes
the overlay/disk generation; extending the method to other modes would require
new keying or stronger ownership. No current caller violates that boundary.

URI aliases, compile results, occurrence indices and lint findings are all
dropped on accepted source mutation, open/close or relevant watched events.
Indices/lint retain the exact checker.Program whose identities they describe;
consumers read these arrays and do not mutate them. Graph-specific lint
suppression and final diagnostic ordering/versioning remain unchanged.

Strict workspace checks are still transient and not registered in session
analysis/index maps. The code does not introduce an O(N²) retained family of
selected-root dependency closures. Rename before and after do not share results
across their distinct overlay snapshots. Existing complete search coverage,
location deduplication, returned edit versions, capture checks and full
before/after validation remain present.

Workspace discovery deduplicates equal root/mode walks. Its roots remain the
selected raw spellings, so some symlink-equivalent walks can remain duplicated;
this is conservative and not a correctness blocker. No claim that all canonical
alias spellings are deduplicated is warranted.

## Scheduling and transport assessment

Only the serial server loop mutates documents/caches. Each didChange keeps the
existing local-copy transaction for ordered range edits; invalid/stale changes
do not alter docs or erase pending dirty work. Consecutive already-queued change
notifications are batched up to 32 or a 25ms scheduling budget, then diagnostics
are published. An empty queue publishes immediately. A non-change frame is kept
as the next ordering barrier and processed only after the pending publication.
Queue closure, framed EOF, close and shutdown all flush accepted state. Close
then clears diagnostics and invalidates all cache maps.

The global dirty flag is sufficient here: publication is serial and reads every
current document's accepted version directly. There is no asynchronous retained
publication carrying stale versions. A separate dirty-version map would add
state without improving the current ordering guarantee. The 25ms check bounds
batch scheduling work, not completion of one compiler check or a blocked output
writer; documentation does not promise a hard diagnostics deadline.

The transport retains its 32-frame queue and separate mutex-protected pending
cancellation map. Already-observed cancellation bypasses expensive request
dispatch; the final cancellation check still closes races before the response.
Workspace discovery/file/check/index phase boundaries stop canceled requests
without publishing partial success. Rename errors are overridden by the final
RequestCancelled response when the request cancellation is pending.

Uncanceled workspace/reference/rename logic still traverses the original files
and checked identities; adding cancellation callbacks does not replace semantic
resolution or reduce checking coverage. A compiler check or sourceIndex already
running remains nonpreemptible, and a cancellation behind an unread full queue
can still be delayed. These limits are explicitly retained in documentation and
the accepted design. Cancellation test counts primarily establish deterministic
discovery/phase boundaries; the wire cancellation sample is an observation,
not a worst-case preemption guarantee.

## Validation evidence inspected

These are parent-produced results inspected by this reviewer, not newly run
checks or guarantees for every possible input:

- `stage3-tests.log`: full pkg/tooling/lsp pass, 3.766s.
- `stage3-race.log`: pkg/tooling/lsp race pass, 26.764s.
- `stage3-scheduling-tests.log`: selected scheduling regression pass, 0.183s.
- New tests require index/lint reuse with meaningful findings, actual imported
  type errors and disappearance on revert, distinct fallback identities,
  Program==nil default errors, nested manifests/alias sets, new confined overlays,
  symlink conflicts/dangling external links, discovered invalid library tests,
  sequential UTF-16/CRLF edits, stale-version rejection, latest invalid source,
  bounded batches over 32 frames, request/close/EOF/shutdown boundaries and
  pre-dispatch cancellation without cached analysis.
- The uncanceled workspace test requires all 12 declarations and all three
  declaration/import/use reference locations. It also rejects canceled partial
  symbol/reference/rename outputs. Full existing package tests cover standard
  navigation, incomplete private completion, cross-file rename and position
  consumers in addition to the new targeted cases.
- `protocol-equivalence/summary.json`: all 16 complete captured method/diagnostic
  payloads match baseline a988, with no mismatches. This includes nonempty
  completion, checked semantic tokens, references, workspace symbols, rename
  and error diagnostics; the typeDefinition fixture result is null on both
  sides and is not independent evidence of positive type-definition behavior.
- `snapshot-memory-summary.json`: three repeated post-GC samples show ten open
  document aliases retaining one Program after the change instead of ten.
  Median heap increase falls from 37,355,960 to 3,737,816 bytes (about 90%).
  Closing/invalidation returns within 4,136 bytes of baseline. This measures
  retained heap for the supplied library workload, not RSS or peak memory across
  every workspace graph. Static inspection additionally confirms no strict
  workspace closure retention.
- `stage3-wire/summary.json`: meaningful feature results retained; 20-sample
  ten-tab warm hover/semantic medians are about 0.13/0.40ms; ten-tab edit to all
  diagnostics about 13.1ms. Burst medians use only three samples; canceled
  workspace/following-hover observations use one sample. Those low counts are
  not tail-latency guarantees. Uncanceled workspace search/references remain
  around half a second because strict selected-root checking is preserved.

The implementation stays within the smaller independently approved design and
resolves the precommit concerns. Remaining limits are bounded, visible and
documented. No stage 3 code blocker remains at the accepted SHA.
