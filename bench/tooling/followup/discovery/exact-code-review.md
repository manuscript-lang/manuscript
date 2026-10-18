# Discovery stage 1 exact-head review

**Disposition: ACCEPT corrected exact head `082c74274e437bf540ee6834f45c2ca835e5f7d6` for code correctness and the stated physical-traversal operation reduction. No correctness blocker remains.**

**Final publication decision: HOLD / WITHHOLD.** After reviewing the measured tradeoff, the parent withheld canonical stage 1 from production: only 1–4 callback visits are saved, with unchanged discovery reads and additional strict selected-context checks. Correctness acceptance does not authorize publication as a performance improvement. The short generated closed-candidate grouping proposal was reviewed and rejected as unjustified for this benefit; see `discovery-generated-scope-review.md`. No additional canonical implementation is authorized. Owner watcher work proceeds separately without workspace/discovery production changes; retain the canonical source patch and probes as a research artifact only.

Base: `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`.
Reviewed isolated checkout: `/workspace/manuscript-tooling-discovery-stage`, clean at the corrected exact head. Scope is only `pkg/tooling/lsp/workspace.go`, `discovery.go`, and `discovery_test.go`. The author's ongoing owner/watch stage was excluded.

**Material performance limit:** this is not an accepted end-to-end speedup. Discovery now retains each lexical alias selection context and can perform more strict compiler checks. The count probe's overall Go test time increased from 3.37s to 11.48s; those are not controlled latency samples, but the extra compiler work is real enough to prevent a latency-improvement claim. The parent must evaluate this stage as physical traversal reuse/correct alias coverage, or together with separately measured owner-stage benefits.

## Review and checks performed

Read the full original `b49 → fd6fe456` diff, the full corrective `fd6fe456 → 082c7427` diff, the approved amended plan/matrix, current compiler path/overlay/selection behavior, production tests, and final external evidence. Read the additional private-overlay/content-cache test added after the first correction draft.

Light verification:

- Exact checkout/HEAD and clean status confirmed.
- `git diff --check b49c0c99 082c7427` passed.
- Combined changed-file inventory contains only the three scoped LSP files.
- Verified recorded source SHA-256 values for workspace/discovery/tests against their immutable Git blobs for both measured heads.
- Verified 30 count samples per head, pinned Go 1.25.1, successful normal probes and four expected failing negative controls in stored metadata.
- No heavy Go build/test/benchmark was started by this reviewer during the coordinated author timing window. Supplied execution evidence is distinguished below from these independent static/metadata checks.

The original blocked review is preserved as `discovery-stage1-fd6-blocked-review.md`; its finding applies to the intermediate commit, not the accepted head.

## Blocking regression resolved

The original `fd6fe4567df02c943327a481739afb8a589906e3` unconditionally read every .ms during the physical walk before consulting authoritative editor snapshots. Base discovery seeded snapshots first and skipped their disk reads. A read error on an existing open file could therefore abort discovery and lose sibling symbols/references despite a valid overlay.

The correction removes content reads from the walk. `walks` stores physical paths only. Candidate assembly resolves represented paths, ambiguous physical text and unique admitted overlay text before consulting a separate request-local closed-content map or reading the filesystem. Successful closed reads are cached; private/open text and read errors are not cached as disk content. This preserves overlay authority without giving up ordinary closed-read reuse across aliases.

The external read-error control injects os.ErrPermission only at LSP discovery's read boundary. Base b49 and corrected 082 pass with main/value/sibling symbols, exactly three declaration/import/use references and zero reads of the open-backed file. Removing the open snapshot produces the intended closed-file error. Exact intermediate fd6 fails by losing the sibling symbol. This is a substantive counterexample and correction control, not a no-op mock check.

The new production assertion checks that the authoritative file never enters the closed-content cache while its closed sibling does. `TestDiscoveryContentCacheDoesNotCapturePrivateOverlays` reuses one helper across two different private snapshots and a later closed-file selection: private requested text remains current and the later closed candidate uses real disk text. It does not accidentally cache private placeholders as filesystem content.

## Final implementation assessment

No additional correctness blocker found:

- Lexical nearest-manifest selection precedes containing-directory canonicalization. Standalone file targets and symlinked manifest-file destinations do not replace their selected containing roots.
- The physical walk uses the canonical directory and retains the recursive flag. Rebased disk paths retain the caller's lexical selection context; sharing traversal does not share strict checked results.
- Every actual open URI is assembled independently of visited-scope state. Encoded filename variants retain requested text; actual distinct-path symlink conflicts still reach compiler CanonicalOverlay validation.
- The deterministic physical-text table suppresses generated disk variants for admitted divergent text. Unique overlay text takes precedence over stored closed bytes. SourcePath still owns confinement/new-file admission; no dangling link admission or compiler conflict suppression was added.
- Closed symlink files/subdirectories and hidden/vendor/node_modules discovery exclusions remain. No nested-project barrier or compiler source-policy substitution was introduced.
- Only successful completed walks enter the request map. Walk errors/observed cancellation do not become completed entries; an os.IsNotExist partial walk is returned without being cached. Lazy closed read errors propagate except disappeared files, which are skipped. This does not create persistent missing-file or error entries.
- The raw overlay-key loop now has the missing per-document cancellation checkpoint. Walk, actual-document assembly, and disk-candidate loops retain checkpoints; caller/request cancellation still rejects partial request success.
- Helper state exists only within a discovery request/invocation. It stores paths and closed text, no compiler Program/Symbol/Type/index or cross-request graph cache.
- workspaceSymbols retains transient per-selected-document analysis and final location deduplication. This preserves needed lexical distinctions but also explains the compiler-work caveat below.

The change intentionally improves alias-only unopened discovery: the old directory-symlink walk could visit only the symlink entry. When a physical root is also supplied, both versions can return the same eight symbols, while the candidate additionally validates lexical alias contexts. Do not equate equal returned names with equal compiler work.

## Supplied validation and mutation evidence

Final portable bundle: `/workspace/tooling-perf-followup/publication/discovery/`.

Inspected:

- `lsp-tests.txt`: exact-stage1 source-overlay LSP package run passes in 5.004s. The overlay restores server/snapshot and hides separately uncommitted watch code; current stage1 discovery/workspace/test blobs are the tested candidate.
- `baseline-read-error` and `candidate-read-error`: exact heads pass, with the closed-file negative control still rejecting the injected error.
- `fd6-read-error-negative-control`: exact intermediate commit fails with lost sibling.
- `canonical-key-only-negative-control`: final-candidate mutation fails on missing unopened alias sources.
- `drop-overlay-text-negative-control`: mutation fails on stale generated disk text.
- `drop-ambiguous-suppression-negative-control`: mutation fails on an invented third disk variant.

Production tests cover alias-root order, unsaved text, encoded URI output, real conflicts, standalone and symlinked-manifest contexts, private snapshots, recursion and cancellation. Stored negative controls exercise the named invariants. No race-test success is claimed by this reviewer beyond evidence actually supplied; exact-final CI remains the parent's gate.

The portable runner restores immutable LSP sources only. Its metadata records the requested commit's stdlib tree/version pins; future reproductions must also use compatible non-LSP checkout sources rather than silently combine new compiler/stdlib behavior with old metadata. Current base/candidate comparison uses the same non-LSP tree, so this caveat does not invalidate these observed traversal counts.

## Measured scope and do-nothing caveat

The valid fixture has eight standalone source files, one physical root, 1/2/4 directory aliases, both root orders, and five samples per combination (30 per head). Every sample requires exactly all eight expected names with no duplicate symbols.

| Aliases | Base walks / callback visits / discovery reads | Corrected candidate |
| --- | --- | --- |
| 1 | 2 / 10 / 8 | 1 / 9 / 8 |
| 2 | 3 / 11 / 8 | 1 / 9 / 8 |
| 4 | 5 / 13 / 8 | 1 / 9 / 8 |

These counters apply only to discovery's WalkDir/callback/ReadFile boundaries; compiler/project filesystem activity is excluded. They prove fewer traversal calls and 1–4 fewer callback visits in this fixture, with unchanged file reads. They do not establish broad latency, memory, p50/p95, or compilation savings.

Doing nothing avoids the extra alias-context analyses when an equivalent physical root is also present, but leaves the alias-only omission and redundant physical traversals. The accepted implementation favors complete selected-context correctness and keeps future selected-analysis deduplication outside this patch. I have explicitly raised the tradeoff with the parent. No end-to-end speedup or performance-optimality claim is approved.

## Final gate

ACCEPT the exact corrected source above. Do not publish the intermediate fd6 commit alone. Parent-controlled readiness/publication/merge still requires appropriate exact-head CI and an accurate description of the narrow benefit and compiler-work cost. A later combined owner/watch head needs its own review; this verdict does not approve uncommitted stage 2/3 work.
