# Tooling performance review closeout

Reconciled against main `95ec85602c3d08a8de6d96de45df89e80bbd2d2a`.
This closeout changes documentation and external probes only. Held experimental
source is text for reproducible review, not compiled production code.

## Landed changes and measured evidence

| Original area | Disposition |
| --- | --- |
| Duplicate ordinary project checking/lint/index work | Live-generation sharing and queued edit coalescing landed in #658. Strict workspace selections remain transient; exact-selection probes found no within-request duplicates for symbols/references. Rename keeps fresh before/after validation. |
| Repeated semantic module resolution | Module lookup hoisted in #653. |
| Index construction and standard headers | #654 removed repeated header scans/maps; #658 reuses live indexes; #662 reuses that index for rename; #675 adds finite immutable pinned-token reuse. No checked standard identities are globally cached. |
| Cancellation and obsolete work | #655/#658/#662 cover client cancellation, queued edits and phase/file boundaries. Already-running compiler/index work remains nonpreemptible. |
| Position/documentation scans | #654 uses line starts, direct UTF-16 widths and bounded comment spans. Extreme same-line prefix costs remain a static residual. |
| Extension lifecycle and watching | #655 fixes activation/lifecycle/cancellation and narrows the watcher glob. Canonical discovery and selective watcher invalidation were investigated and withheld, as detailed below. Global relevant-event invalidation remains. |

The first four PRs are [#653](https://github.com/manuscript-lang/manuscript/pull/653),
[#654](https://github.com/manuscript-lang/manuscript/pull/654),
[#655](https://github.com/manuscript-lang/manuscript/pull/655) and
[#658](https://github.com/manuscript-lang/manuscript/pull/658). The bounded follow-up
landed [#662](https://github.com/manuscript-lang/manuscript/pull/662) and
[#675](https://github.com/manuscript-lang/manuscript/pull/675). Each passed its
required checks and postmerge CI. #662 and #675 also have confirmed actual Pages
deployments in [39107605141](https://github.com/manuscript-lang/manuscript/actions/runs/39107605141)
and [39109533351](https://github.com/manuscript-lang/manuscript/actions/runs/39109533351).
No live browser freshness claim follows from deployment logs.

The earlier report retains the original cold/warm wire measurements and raw
samples. Warm local prepareRename improved from 17.21–18.87 ms and 22.50 MB/op
to 57.1–62.2 microseconds and 12,240 B/op in three 300ms benchmark observations
on aa3efa72 → 5facbb5f. [Boundary evidence](README.md#rename-index-and-cancellation-boundaries)
includes allocation and deliberate cancellation controls.

After a separate lexer optimization landed, a fresh same-lexer comparison used
`55228347c8555186ab6a483459e161e1bef82326` → merged
`3232c8db008fe60804f88bb8a243d15ce8da0a14`. Warm indexing saves about
**14.327 MB and 1,582 allocation events per call**, at about **4.746 MB fixed
process retention**. Three warm handler observations per size gave symbols
medians 529.466 → 228.648 ms (41 modules) and 1,291.530 → 670.113 ms (101).
All complete payloads and strict counts matched. Cold samples overlap; no cold
startup or general peak-memory improvement is claimed. See the
[integration addendum](current-lexer/RESULTS.md) for exact inputs, sample counts,
current allocation counts and portable raw evidence. Older figures remain dated
to their own revision pairs.

## Withheld remedies and concrete decisions

**General request-local strict graph reuse:** rejected. Symbols/references have
zero measured repeated exact selections. Rename repeats N-1 original selections
across phases, but success reuse would remove fresh filesystem validation and
retaining every checked owner can amplify library graph memory. The
[selection/memory report](selections/RESULTS.md) and
[independent design review](selections/design-review.md) explain the bounded
do-nothing decision. Strict checks were preserved.

**Canonical discovery:** withheld. Thirty samples per head across alias count
and root order saved only 1–4 callback visits, with eight reads on both sides.
Restoring every lexical alias context also introduced additional strict checking.
Whole probe elapsed increased, although that was not a controlled latency study.
Another selected-context identity rule is not justified by the tiny measured
traversal benefit. [Counts, corrected I/O controls, patches and final decision](discovery/README.md)
remain reproducible; none of the discovery source was merged.

**Selective watcher invalidation and dependent batching:** withheld for
demonstrated correctness failures. The normal local-path experiment saved
compilation/publication work, but four cross-owner open-overlay controls failed.
Six additional serial filesystem controls showed stale cached success versus
fresh confinement failure through **closed** relative-import, manifest-alias and
manifest-entry routes. Those routes can lexically leave B, resolve through a
symlink back into B, then become invalid when the outside route is replaced.
Canonical Program module endpoints do not preserve the original route.

The relevant contracts are
[SourcePath](https://github.com/manuscript-lang/manuscript/blob/95ec85602c3d08a8de6d96de45df89e80bbd2d2a/pkg/project/paths.go#L53),
[manifest path canonicalization](https://github.com/manuscript-lang/manuscript/blob/95ec85602c3d08a8de6d96de45df89e80bbd2d2a/pkg/project/manifest.go#L185)
and the currently exposed
[compiler Result](https://github.com/manuscript-lang/manuscript/blob/95ec85602c3d08a8de6d96de45df89e80bbd2d2a/pkg/compiler/compiler.go#L31).
Per-open physical footprints cannot cover unopened routes. A future coordinated
resolver/frontend/compiler proposal should expose complete input-route footprints
or an upstream signal that selective invalidation is unsafe. An LSP configuration
parser or heuristic dependency graph is excluded. The
[final independent HOLD review](owner-watch/final-hold-review.md) and
[bounded future API direction](owner-watch/future-input-footprint-decision.md)
provide concrete requirements without authorizing an implementation. Existing
global watcher invalidation is retained. No selective-invalidation production PR was opened.

## Remaining non-LSP tooling priorities

These are review findings, not implemented speedups. The
[full inventory and independent audit](non-lsp/report.md) cover formatter/lint,
inspection/facts/flow, review/diff, diagrams/views, guide search/pages and docgen.
Historical measurements use 5facbb5f; the listed tooling production sources remain
unchanged at the reconciliation revision, while their dependencies have evolved.

| Rank | Evidence and likely bounded remedy | Confidence/limit |
| --- | --- | --- |
| 1 | No-op CompareFacts chain: 4.20/15.94/69.65 ms and 3.47/13.78/55.04 MB at 256/512/1,024 entities. Compute reverse reachability lazily only for findings that consume it. | High mechanism confidence; synthetic no-op graph workload, five one-iteration repetitions. |
| 2 | Formatter rebuilds the full source for every insertion; the profiled line accounts for about 55.9% of sampled grouping allocation. Apply edits in one builder pass, preserving byte order/comments/idempotence. | High source/profile confidence; lexer/parse work also contributes and has since changed. |
| 3 | Warm guide Page(json): 16.13 ms/15.97 MB versus identical pre-materialized rendering at 0.031 ms/8.6 KB. Consider private immutable guide metadata. | Measured historical materialization cost; public checker detached-snapshot contract must remain. |
| 4 | BuildView returns 300 independent roots despite nodeCap 200; modules view also lacks the cap. Enforce one deterministic output budget. | Reproduced output-bound gap, not a latency inference. |
| 5 | Docgen SiteFiles materializes detached standard documentation twice. Render from one held snapshot. | Source-proven duplicate work; no end-to-end measured speedup. |

The earlier duplicate CLI Inspect observation is **resolved by
[#671](https://github.com/manuscript-lang/manuscript/pull/671)** and is not an open
recommendation. Source-driven lint and checked-chain Inspect/Facts controls
scaled approximately linearly in the measured fixture; unmeasured long-line,
high-fanout and nested-callback suspicions remain labeled as such.

## Limits and baseline failures

No in-repository MCP server exists in the reviewed sources; the removed #528
proposal, external integrations and current CLI agent commands are distinct.
No MCP server was added. End-to-end VS Code editor-host startup, visible typing
latency and host memory remain unavailable. Wire/handler/helper measurements and
static client protocol review are separately labeled. The available Node was
24.19.0 versus repository pin 24.13.0; Go was the pinned 1.25.1 on Linux amd64.

Result-returning Manuscript assertion controls were deliberate: positive exits 0,
`try assert_true(false)` exits 1 and ignoring the assertion Result exits 0.
Published probes preserve full payload assertions and expected-failing controls.
The historical main CI #643 FuzzFormat deadline timeout had no minimized
counterexample and remains a separate baseline observation, not a proven
regression from these changes. Later required checks and postmerge runs passed.

No claim that every tooling operation is extremely efficient follows from this
review. No incremental compiler, cross-generation checked cache, concurrent
checking, internal compiler preemption, MCP implementation or unrelated Delve
change was introduced.
