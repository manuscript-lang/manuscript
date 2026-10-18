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
required exact-head CI supplies the integrated race gate. Repo-check passed.
Five mutation/old-code controls fail by their intended assertions: post-index
selection, per-file edit construction, post-before-check cancellation,
post-analysis indexing and continuing discovery scopes. Raw failure logs remain
beside the benchmark output. Independent review accepted the production SHA.

## Coverage is still being completed

| Original remedy | State after this stage |
| --- | --- |
| Equivalent ordinary project checks/lint/indexes | Shared within a live generation; strict workspace selections still transient |
| Repeated semantic module resolution | Fixed previously |
| Repeated indexing | Headers/maps/live indexes and rename reuse fixed; immutable standard lexical reuse under design review |
| Queued obsolete diagnostics and cancellation boundaries | Bounded batching and phase/file guards landed; compiler/index preemption excluded |
| Whole-source position/documentation scans | Replaced by line starts/direct widths/bounded comment spans; extreme same-line prefixes remain |
| Extension lifecycle/cancellation/watching | Lifecycle/tokens/narrow glob fixed; canonical discovery grouping and owner-based invalidation under review |

Workspace exact-selection counts, sampled peak memory and filesystem consistency
must justify any additional reuse before implementation. Retaining one strict
graph per selected module and replacing strict checks with recovering graphs are
excluded. A new non-LSP tooling inventory is separate from these LSP measurements.
