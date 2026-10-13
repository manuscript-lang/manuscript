PR #238 remains held in draft. No Release patch is promoted from these
experiments: the measured runtime increases violate the current direction to
preserve fastest Release execution. The effectful-element and Debug-only paths
are evaluated separately from the confirmed scalar-copy cost.

## Effectful-element split

The independent baseline is main
`7bd79bb027f5aeb60fda55f25671f3d0c309d245`. It includes #214's
source-frame/runtime changes. Every
variant is built against that same runtime, using bundled Go 1.25.1. Scalar
table copying is absent from every effectful candidate.

The actual source workload constructs a fresh Counter and calls a source `tick`
for every element; tick mutates the counter and returns its value. The cheaper
control calls a source function returning constant 1. Native parity checks
verify every produced element. Pinned CPU 0, GOMAXPROCS=1, GOGC=100, seed 147
randomizes variant order. Ratios use paired log-ratio bootstrap intervals, as
described in runtime-review.md.

| Candidate, 1,100 calls | Mutating call ratio / 95% interval | Cheap call ratio / 95% interval |
| --- | --- | --- |
| 64-assignment slice closures | 1.028 / 1.003–1.051 (32 pairs) | 1.057 / 1.021–1.089 (24 pairs) |
| 64-assignment fixed-array closures | 1.023 / 1.006–1.040 (32 pairs) | 1.033 / 0.994–1.062 (24 pairs) |
| Explicit helper parameters | 1.021 / 1.005–1.038 (40 pairs) | 1.061 / 1.038–1.086 (40 pairs) |
| One ordered initializer, no chunks | 0.997 / 0.949–1.048 (24 pairs) | 0.983 / 0.928–1.034 (24 pairs) |

The initial shorter samples overlapped equality. Longer measurements expose
small costs in the chunked variants, so they are not called nonregressing.
All retain allocation counts for their matched workload. The single initializer
is closer to runtime parity but worsens native compilation.

| Mutating calls | Original build / RSS / bytes | 64 fixed-array helpers | Single initializer |
| --- | --- | --- | --- |
| 1,100 | 17.5 s / 1,305,296 KiB / 6,492,344 | 1.42 s / 181,180 KiB / 5,951,672 | 24.7 s / 2,832,200 KiB / 5,959,864 |
| 1,600 | 25.8 s / 2,709,924 KiB / 7,221,432 | 2.07 s / 261,880 KiB / 6,127,800 | 57.2 s / 5,633,296 KiB / 6,148,280 |
| 2,200 | 46.5 s / 5,201,960 KiB / 8,347,832 | 2.83 s / 338,088 KiB / 6,344,888 | 113.9 s / 9,174,268 KiB / 6,373,560 |

These build samples compare forced application edits with warm dependencies.
They show a useful compilation boundary, not an acceptable Release runtime
tradeoff under the current instruction. No broad AST/ABI changes were made.

A future narrow implementation must retain source-call/default argument order,
one evaluation per element, mutable binding reads between elements, shared
sourcePosition/cleanup/type-evidence state and nonlocal return/try/loop exits.
Parameterized helpers cannot snapshot mutable bindings for an entire chunk;
they would need checked eligibility or reference-preserving parameters. Arrays
must be newly allocated each evaluation, including defaults; nested objects and
aliases remain references. Generic/contract evidence and fault directives must
remain unchanged. Passing the simple tick parity checks alone does not prove
all of these contracts. Existing #238 semantic tests remain the broader oracle,
with their independent source/Go files untouched.

Recommendation: do not split the tested helpers into a ready Release PR yet.
Keep #147 open for scalar and other flat-literal residuals. The prototype
worktree branch `perf/147-effectful-literals` has no production edits or commits.
New #214 TraceSource signatures also require an explicit compatibility adapter
when running the older frozen Go oracle on a later runtime; preserve the file's
hash/provenance instead of silently regenerating it.

## Debug-only design option (not implemented)

Existing command behavior provides a clear user boundary: Debug disables Go
optimization/inlining, while Release is the default. `--debug` is already an
alias; `debug` forces Debug, and `profile` defaults to RelWithDebInfo. A policy
restricted to explicit Debug can retain the fastest existing scalar lowering
for Release, RelWithDebInfo and MinSizeRel without changing defaults or ABI.

Warm dependency caches, three alternating forced-edit samples, current-main
scalar source, bundled Go flags matching Debug:

| Int elements | Existing Debug median / RSS / bytes | Copied-data Debug prototype |
| --- | --- | --- |
| 16,000 | 2.318 s / 274,264 KiB / 12,239,774 | 0.460 s / 113,620 KiB / 11,330,395 |
| 100,000 | 13.148 s / 1,580,892 KiB / 19,030,960 | 1.573 s / 178,096 KiB / 13,345,635 |

The cold first sample is retained separately and not used for these medians.
No Debug runtime speed claim is made. The copied data is still immutable
primitive input copied into fresh mutable storage, not globally shared Lists.

This is a natural CLI build-level boundary, but **not currently a lowering
boundary**. `compiler.Options` has no build type. CompileSource/CompileFile
produce Result.Source before BuildCheckedWithType selects native flags.
Changing a Go compiler flag alone cannot choose another representation.

Two implementation options require review first:

1. Carry an explicit lowering build type in Options and the Result recipe.
   Native CLI already resolves `kind` before CompileFile; pass it there and
   through watch/debug/profile paths. Existing API calls default to Release.
   BuildCheckedWithType must regenerate a mismatched recipe rather than
   silently use Debug lowering for Release. Existing CompileSource-default →
   BuildChecked(Debug) calls must keep working; a new mismatch error on this
   existing path would be an API regression. Unchecked BuildWithType keeps the
   caller's supplied Go source.
2. Retain the checked program, entry and lowering options as a private recipe,
   then re-lower for Debug at BuildCheckedWithType. This preserves public
   CompileSource defaults but adds a second generation pass and must preserve
   profile/test/launcher options. It also needs a clear policy for callers that
   intentionally modified Result.Source; silently discarding their source is
   unacceptable.

Cache plumbing is favorable: build identity already includes BuildType and
GeneratedSHA256, and Debug source paths already participate. Source-only checks
must continue to stop before lowering. Emission defaults, all four build levels,
cache separation, offline distribution, debugger stepping/locals/fault frames,
mutable freshness, aliases and independent baseline provenance need validation.
Never regenerate an oracle to accommodate the policy.

Recommendation: review native build-time lowering from a retained private
recipe (option 2), with optional earlier selection for CLI to avoid generating
twice. It preserves existing API default paths and uses no new command flag or
changed default. Resolve intentional Result.Source overrides explicitly before
implementation. It improves Debug editing workflows while the Release scalar
issue remains open. Implement neither option before review.

## Retained evidence

Raw paired samples/build samples are in results/effect-split/. Generated
Manuscript/Go, all prototypes and binaries are
retained locally under `.artifacts/flat-literals/effect-split/` and the isolated
worktree `.artifacts/` directories. One initial build linked new #214-generated
source against the older runtime and failed in the tool transcript; all reported
comparisons were rebuilt against the matching current-main runtime. That failed
attempt is not reclassified as a passing run.
