# Independent exact-head review: first bounded follow-up

**ACCEPT `5facbb5ff966904e0b6fe918245d7df7885937ff`.** No code or test
blocker found in the six-file diff from main
`aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
Candidate tree: `cd2e2cbc67318705f6127886c728e1dd152079a1`.
Required CI remains the parent's publication/merge gate. Later commits require
an exact-head refresh; this does not approve broader workspace/stdlib reuse.

Read-only review in `/workspace/manuscript-tooling-followup` at the exact SHA
above, with clean working tree and clean diff whitespace check. Inspected the
entire production/test diff and the parent-supplied test/benchmark controls.
The repository workflows/experts and compiler/project contracts were already
read for the preliminary review. No source/test edits or tests/benchmarks run by
this reviewer, respecting the delegated measurement CPU slot.

## Production conclusions

The LSP rename path now supplies its already-owned occurrence index for the
same immutable checked Program. It neither replaces checked identity with
spelling nor reuses a different strict/recovering selection. The default wrapper
still builds its own index for callers without one. renameIndexed's entry
checkpoint catches cancellation that arrived during construction, and the live
cached slice is only read.

The final candidate adds the missing post-index boundaries for semantic tokens,
hover/definition, type definitions and highlights. References and rename already
have a helper-entry checkpoint after their argument index is evaluated. Along
with post-checkedDocument guards, these prevent a request whose cancellation is
now observed from starting its next feature phase. The existing final Serve
check turns the internal nil return into RequestCancelled; it does not expose a
successful empty result for a canceled request. Pending cancellation reads use
the existing mutex-protected transport state, with no new concurrency owner.

renameChanges and validateRename preserve the previous algorithm while making
construction/strict-validation phases testable directly. Construction still
sorts URIs and descending offsets, reads original source, rejects capture,
returns original versions, and keeps modified overlays private. Cancellation at
a file boundary discards both edits and overlays. Validation still freshly
checks every original selected root and every proposed-source selected root in
the same order, with all post-check checkpoints. No request-local graph memo or
stale validation status is introduced; filesystem/manifest/alias behavior stays
with the original compiler/project APIs.

Discovery stops immediately when a scope returns context.Canceled and checks
between open-document copies and additional roots. Without cancellation,
traversal, exclusion, ordering and complete results are unchanged. No partial
successful result, arbitrary limit or skipped strict validation produces the
speedup.

## Tests inspected

New tests target the post-check boundary without production hooks, require no
derived index when canceled, then require a meaningful uncanceled result and
live index. A custom user Item supplies a positive typeDefinition control.
The post-index rename test requires cancellation to beat a deliberate unresolved
selection error, with the uncanceled error as a distinguishing control.

Edit-phase tests require nil partial results, unchanged input documents and
immediate cancellation before a deliberate second-file lexical error; the
uncanceled control must reach that error. After repair, both rewritten files and
the original document version are required. The strict before-check control
enters validateRename directly, deliberately changes an imported disk file,
and requires post-check cancellation rather than a workspace error. Existing
integration rename tests remain necessary; the production caller visibly still
calls this strict validation phase.

The prepareRename regression uses a valid resolved local binding, compares the
exact returned range/placeholder with the old uncached helper, requires the same
live slice identity, and uses allocations relative to rebuilding the full index
on that same checked Program. Its ample relative bound is not a timing test and
would reject a change that merely suppresses the result. The supplied old-source
negative control fails for the intended reason: about 58,386 prepare allocations
versus 58,302 full-index allocations. It is not a setup/build failure.

The added generic post-index guards are simple read-only checks inspected
directly; the focused tests do not claim to interrupt compiler or sourceIndex
internals. The new code does not create hooks or worker concurrency solely to
simulate such preemption.

## Evidence and limits

Inspected parent-produced logs, not newly run checks:

- Final full LSP suite: PASS, 4.226s.
- Earlier LSP race suite: PASS, 27.076s; repo-check PASS. These precede only the
  final extra read-only post-index checkpoint additions. They should not be
  labeled a fresh race run of the final SHA until rerun/CI establishes that.
- Identical 40-module/20-function prepareRename helper, three 300ms benchmark
  estimates: before 17.21–18.87ms/op, about 22.50MB/op and 82,753–82,754
  allocations/op; after 57.06–62.22µs/op, 12,240B/op and 117 allocations/op.
  Raw iteration counts range 18–20 before and 6,111–6,418 after. These are Go
  benchmark means, not editor latency percentiles or broad workspace speedups.
- The baseline allocation negative control fails its intended assertion, as
  described above. Further external mutation controls were still running or
  pending at this review; no pass claim for those is made here.

One compiler check, index construction, lex or string rewrite remains
nonpreemptible. The new checks stop work at observed boundaries rather than
promising a hard cancellation deadline or bypassing unread saturated input.
Fresh strict workspace checks and before/after rename scopes remain separate
and transient. The broader exact-selection and standard lexical reuse proposal
is still awaiting evidence under `reuse-design-review.md`.

This is a bounded independently justified improvement with no outstanding
correctness concern at the accepted exact SHA.
