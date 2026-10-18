# Completing the bounded tooling remedies

Original findings are tracked in the [first review and measurements](../README.md).
This follow-up starts from main `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`,
which includes the earlier fixes plus the current Result/Optional API renames.
No compiler, project, frontend, checker or runtime implementation is changed.

## Rename index and cancellation boundaries

Production candidate `5facbb5ff966904e0b6fe918245d7df7885937ff` reuses the live
checked index for rename/prepareRename. It checks cancellation after ordinary
checking, before/after indexing, between rename edit files and strict validation
checks, and before additional discovery scopes. Only complete edits/results are
returned. Already-running compiler/index work remains nonpreemptible.

The existing rename edit-construction and strict-validation phases were factored
into helpers so deterministic tests can enter a phase directly and prove the
next operation does not run after cancellation. Tests preserve exact resolved
ranges, original document versions, complete uncanceled edits and live index
identity. A malformed second source file and a strict-check failure distinguish
cancellation from later normal errors. No timing sleeps or compiler hooks.

Same-host Go 1.25.1 Linux/amd64 EPYC 9V74, GOMAXPROCS=4, three 300ms-target
benchmark means, 41 modules / 801 functions, warmed live analysis/index:

| Local prepareRename | Before | Candidate |
| --- | ---: | ---: |
| Time/op | 17.21–18.87 ms | 57.1–62.2 µs |
| Bytes/op | 22,502,837–22,502,975 | 12,240 |
| Allocations/op | 82,753–82,754 | 117 |

These are request-handler helper means, not editor or cold-request percentiles.
Raw iterations are retained in [boundaries](boundaries/). The new relative
allocation control fails against the old implementation: prepareRename allocates
58,386 times versus 58,302 for rebuilding its index. The candidate preserves
the same resolved range while avoiding index-sized allocation.

```sh
toolchain/go/bin/go test ./pkg/tooling/lsp -run '^TestPrepareRenameReusesLiveIndex$' -count=1
toolchain/go/bin/go test ./pkg/tooling/lsp -run '^$' -bench '^BenchmarkPrepareRenameLiveIndex$' -benchmem -benchtime=300ms -count=3
toolchain/go/bin/go test ./pkg/tooling/lsp -count=1
toolchain/go/bin/go test ./pkg/tooling/lsp -race -count=1
```

For an old-checkout control, supply the new `rename_reuse_test.go` using Go's
`-overlay` mapping to that same relative path in the old checkout. The test uses
only pre-existing server APIs and the unchanged performance fixture. The
allocation test must fail on the baseline; use `-run '^$'` for its benchmark.

All focused and full LSP tests passed (final package run 4.226s). The race suite
passed in 27.076s before the final additional read-only post-index guards;
[exact-head CI/CD 39107090788](https://github.com/manuscript-lang/manuscript/actions/runs/39107090788) passed the integrated race gate. PR #662 merged as `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`; [postmerge CI/CD 39107605141](https://github.com/manuscript-lang/manuscript/actions/runs/39107605141) and its actual Pages deployment also passed. Repo-check passed.
Five mutation/old-code controls fail by their intended assertions: post-index
selection, per-file edit construction, post-before-check cancellation,
post-analysis indexing and continuing discovery scopes. Raw failure logs remain
beside the benchmark output. Independent review accepted the production SHA.

## Bounded review disposition

| Original remedy | State after this stage |
| --- | --- |
| Equivalent ordinary project checks/lint/indexes | Shared within a live generation; strict workspace selections still transient |
| Repeated semantic module resolution | Fixed previously |
| Repeated indexing | Headers/maps/live indexes and rename reuse fixed; finite pinned lexical reuse validated below |
| Queued obsolete diagnostics and cancellation boundaries | Bounded batching and phase/file guards landed; compiler/index preemption excluded |
| Whole-source position/documentation scans | Replaced by line starts/direct widths/bounded comment spans; extreme same-line prefixes remain |
| Extension lifecycle/cancellation/watching | Lifecycle/tokens/narrow glob fixed; canonical discovery and selective watcher invalidation withheld after the measured/correctness review below |

Workspace exact-selection counts, sampled peak memory and filesystem consistency
were evaluated before additional reuse. The [closeout](CLOSEOUT.md) records the
accepted changes and withheld proposals. Retaining one strict
graph per selected module and replacing strict checks with recovering graphs are
excluded. A new non-LSP tooling inventory is separate from these LSP measurements.

## Finite standard lexical reuse

Production candidate `9c2296984c92a2f90c08c1353775150802765bae` caches only
immutable lexer tokens for the binary's finite pinned standard source inventory.
Both filename and source must match exactly. The cache retains pinned strings,
never caller strings, checked graphs, symbols, types or workspace text. Arbitrary
inputs cannot add keys; initialization is lazy and race safe.

[Complete results, cold/warm separation and absolute memory](lexical/RESULTS.md)
show about 14.43 MB less allocation per warm index. At 101 application modules,
three repeated warm handler medians changed: symbols 1,444→604 ms, references
1,207→558 ms, rename 1,300→562 ms. Complete occurrence and returned workspace
payloads match; strict before/after checks are unchanged. This costs about
4.858 MB fixed process retention. Cold ranges overlap, and sampled absolute peak
heap is not uniformly lower. These are handler/index measurements, not editor
latency or startup claims.

The [exact-selection counts and peak-memory investigation](selections/RESULTS.md)
reject a general request-local checked-graph cache: symbols/references show no
exact duplicate selections; rename's repeats require preserving fresh filesystem
validation and would otherwise retain many full owners. That is a deliberate
bounded design decision, not an implemented workspace-result cache.

Full LSP race tests passed (13.111s), including a separate fresh-process concurrent
first-use run (1.847s). Built binaries preserve all 16 captured feature/diagnostic
payloads; Result assertion controls produce expected exits 0/1/0. Removing exact
source equality fails the fallback test. Repo-check passed. The private cache's
[design](lexical/proposal.md), [independent decision](lexical/design-review.md),
[review](lexical/review.md), raw logs and portable probes are retained.

## Non-LSP tooling inventory

The [separate read-only assessment](non-lsp/report.md) covers formatting, lint,
inspection/facts, review/diff, diagrams/views, guide search/pages and documentation
generation. It records measured no-op review growth, formatter copy costs and
repeated guide metadata, plus an output-cap reproducer and bounded fix candidates.
No non-LSP implementation change accompanies this report. [Independent evidence
review](non-lsp/review.md) verified the source/probe hashes, all 21 benchmark cases
and profile attribution. CLI duplicate inspection is a cross-owner observation.

## Final reconciliation and integration

The [concise closeout](CLOSEOUT.md) ranks remaining work and records the exact
landed/withheld boundary. The [newer-lexer addendum](current-lexer/RESULTS.md)
refreshes the cache cost after main changed: about 14.327 MB less allocation per
warm index at a fixed retained cost of about 4.746 MB. Earlier tables remain
historical. [Canonical discovery](discovery/README.md) and
[owner watcher invalidation](owner-watch/README.md) are research artifacts only;
neither production patch nor watcher batching was merged.
