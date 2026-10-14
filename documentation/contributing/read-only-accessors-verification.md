+++
title = "Read-only accessor implementation evidence"
weight = 28
+++

# Read-only accessor implementation evidence

The implementation follows the [approved design](read-only-accessors-design.md).
It is prepared for independent final review; no pull request has been published.
The parent relayed explicit independent approval of design commit
`46c46a29105e1aabb969d22cce96825b52dc0b8a` before implementation began.

## Scope and integration base

The comparison base is merged `main` at
`1383851ebb24d2dc8a0a13d8cec0021bf32e833d`, including #497, #501 and #503.
The stopped broad performance branch and unmerged debugger work were not used.

The exact inventory test covers the approved **56 method migrations** and the
three existing Int unit properties. All use the same `get name -> T` declaration
mechanism. Duration projections use the six unit nouns; guard payload reads use
`value`. Discovery-based tests retain `Error.message()` and every current standard
implementation as methods, including deferred bound-method references.

The implementation retains one annotated syntax tree. Accessor identity is a
member-kind flag, carried through checking, interface conformance, effects,
lexical implementation evidence, dispatch and tooling. Concrete native reads use
typed result helpers; source reads use direct functions where eligible, and
receiver-only dispatch otherwise. Dispatch caches targets rather than values.

The #503 integration preserves its unrelated scalar functions and Optional
`unwrap_or` fast path. Its static Optional flag path has an admission-only
cancellation check; the new flag helpers preserve that contract. Dynamic reads
retain their delivery check. A deterministic regression distinguishes these
boundaries without relying on scheduling.

## Observable compatibility changes

- Approved getter calls become property reads. Old noncallable accessor calls
  receive actionable diagnostics, with safe edits for empty calls.
- A stored accessor expression reads immediately. Deferred reads use an explicit
  closure that captures the intended receiver.
- Accessors remain live, evaluate the receiver once, reject assignment, preserve
  absence and mutable aliases, and retain resource, guard and effect contracts.
- Documentation/API JSON and inspection JSON use format **2** to expose accessors
  separately from fields and methods. Completion inserts a property read.
- Existing actions, conversions, snapshots and Error methods remain callable.

The changed benchmark reference for c13 also replaces one pre-existing stale
`Map.with_default` call with the existing `add_default` method so the reference
can execute against current main. This changes no language or runtime API.

## Verification record

Commands use the repository's pinned Go 1.25.1 SDK. This workspace requires writable
caches and disabled worktree VCS stamping for direct Go test invocations:

```sh
export GOCACHE=/tmp/manuscript-accessor-go-cache
export GOPATH=/tmp/manuscript-accessor-go
export XDG_CACHE_HOME=/tmp/manuscript-accessor-cache
export GOFLAGS=-buildvcs=false
```

`make -o payload ...` reuses the already verified embedded SDK payload rather than
repackaging its unchanged contents for every command.

| Check | Evidence |
| --- | --- |
| Routine repository gate | `make -o payload verify` passes after integration with #503: formatting/vet, pinned linters, repository rules, unit tests, standard source checks, source documentation, examples and licenses. |
| Standard inventory | Exact 59-accessor names, result signatures and ABI categories agree in both directions. Tests discover Error implementations and retain noncandidate method controls. |
| Parser | Strict and partial parsing, visitors, contextual `get`, source positions, and 10-second strict/partial fuzz runs pass. |
| Checker and lowering | Full checker/lower/compiler suites pass; focused cases cover kind mismatches, visibility, generic evidence, read-only assignment, safe migration edits, callable results, effects, `try` order, recursion and typed flags. |
| Native build suite | Full `pkg/build` passed before #503 integration. All four accessor native integration tests pass again after rebase, including source scopes, source implementations of standard contracts, fault frames, depth and cancellation. |
| End-to-end suite | The complete run exercised execution/conformance cases successfully. It found one standard-export formatting failure; formatting all 44 standard modules fixed it, and the exported-source test passes on retry. |
| #503 integration | Optional member, scalar standard function, overflow, CLI documentation and exported standard-source tests pass after rebase. |
| Tooling | Full tooling suites, full LSP race suite, accessor-focused race checks, and API/inspection regressions pass. |
| Runtime race | The complete runtime race suite passes in isolation after #503 integration, including the final Optional cancellation regression. |
| Native debugger | Opt-in extension checks: 24 passed, zero skipped. A source getter stops at its named body; field expansion and plain record watches do not invoke it. |
| Standard source formatting | `ms fmt pkg/stdlib --check` passes for all 44 modules. |
| Changed benchmark references | All 10 Manuscript references and 152 hidden oracle cases pass; the five Python harness tests pass. |
| CLI and examples | Remaining internal/CLI, scripts, ABI, standard inventory and native tutorial-example suites pass after integration. |
| Standalone distribution | Linux/amd64 package verification passes with empty caches, system Go and dlv absent, and downloads disabled: compilation, source tools, LSP, terminal/DAP debugging and profiles. The verifier now expects the deliberate API JSON format 2. |
| Formatter/compiler fuzz smoke | Ten-second runs pass with explicit accessor declarations and old-call diagnostic seeds. The formatter run executes only seven inputs on this host, so it is a bounded smoke check rather than broad fuzz coverage. |
| Book | Source descriptions, generated API references, highlighting, strict Hugo build and publication/link checks pass. |

The called accessor fixtures cover live reads, receiver count and order, short
circuiting, function-valued getters, mutable and nested Optional aliases,
ClientResponse head replacement, units and rounding, validated guards, source
implementations of native-looking interfaces, local generic implementation scopes,
fault lines, recursive depth and cancellation. Resource metadata remains available
after close according to each existing contract.

## Performance evidence

The historical audit in the design predates #503. Actual emitted Go from the
comparison base partitions the 20 core workloads into **8 direct helpers,
7 hoisted native calls and 5 fully bound calls**. Optional presence checks are
already direct on this base; Bytes.length, Result flags and Float classifiers
remain fully bound. All 20 current core reads use direct typed helpers. The
emission check rejects bound Function construction, Invoke, Bind, CallNative,
BindNativeCall and dynamic ReadAccessor in these statically resolved reads.

The harness and reproduction commands live in
[scripts/bench-accessors](https://github.com/manuscript-lang/manuscript/tree/main/scripts/bench-accessors).
It retains checked source, emitted Go, escape analysis, parity/cancellation tests,
native samples, source/output hashes, SDK/environment metadata, and an emitted
call inventory. Each measured operation performs **1024 reads**. Native samples
use one CPU; compilation and startup are measured separately from read loops.

Measurement host: Linux/amd64, Intel Xeon Platinum 8573C, five available cores,
Go 1.25.1. Results are specific to this host and the retained inputs. The
comparison script reports medians, allocations and an exploratory exact
permutation test without a multiple-comparison correction; this is not a general
claim that property spelling alone improves performance.

Both revisions pass native parity and cancellation checks. The quiet paired run
contains five 200 ms samples for each of 52 workload/data variants. Representative
medians follow; times and allocations are **per 1024-read operation**, including
the source wrapper, loop, setup and nested work in that workload.

| Workload | Baseline ns/op | Accessor ns/op | Baseline allocs/op | Accessor allocs/op |
| --- | ---: | ---: | ---: | ---: |
| List.length | 6,188 | 4,157 | 1 | 1 |
| Bytes.length | 357,076 | 5,755 | 7,169 | 1 |
| Optional.is_some, present | 5,531 | 4,262 | 1 | 1 |
| Result.is_ok, ok | 525,739 | 5,938 | 9,217 | 1 |
| Float.is_finite, finite | 490,663 | 6,087 | 9,217 | 1 |
| Source interface view | 221,740 | 90,232 | 3,075 | 3 |
| Generic source read | 279,870 | 143,873 | 4,098 | 1,026 |
| Guard payload plus length | 474,172 | 24,011 | 10,268 | 28 |
| ClientResponse metadata/status | 489,381 | 25,460 | 8,208 | 16 |
| Unchanged method control | 8,654 | 8,735 | 1 | 1 |
| Handwritten CollectionLengthInt control | 9,509 | 9,236 | 1 | 1 |

The already direct Unicode String.length workload has a 1.2% higher median
(12,204 to 12,351 ns/op, exploratory p = 0.992). The unchanged-method control is
0.94% higher (p = 0.0238 without multiple-comparison correction); the handwritten
control is 2.9% lower (p = 0.5). These small changes and the controls do not support
a blanket claim that every direct getter becomes faster. The handwritten control
uses the generic receiver switch in CollectionLengthInt, so it is not a claim
about the best possible handwritten specialized List loop.

Source workloads also contain the migrated nested List read. Guard setup and
cleanup remain included. The Logger workload includes LogLevel equality and
transport setup; its measurements do not isolate mutex or dispatch cost. None of
these results establishes performance for unmeasured service or contention paths.

Separate warmed CLI phase medians at N/2N/4N are below, in milliseconds. Each cell
is baseline/accessor, with three samples per phase. The build phase retains warm
SDK/dependency caches and the existing native command replay; it still compiles
and links the application. Startup remains included.

| Read expressions | Check ms | Emit ms | Native build ms |
| ---: | ---: | ---: | ---: |
| 64 | 19.3 / 18.7 | 156.4 / 168.4 | 124.0 / 231.0 |
| 128 | 19.5 / 21.6 | 159.1 / 162.6 | 244.6 / 233.9 |
| 256 | 21.5 / 21.4 | 161.4 / 170.3 | 337.8 / 298.9 |

The 64-read native build is slower on the accessor revision; the larger two are
faster. No current phase grows more than twice when doubling these bounded inputs.
This range is too small and the fixed costs too large to establish asymptotic
complexity or general compile-time improvement. Each emitted/built program passes
its checksum test.

Small raw samples, metadata, emitted-call inventories and the full comparison are
retained under `scripts/bench-accessors/results/`. Larger emitted Go, escape
analysis and native binaries remain in `.artifacts/accessor-bench/` and the
baseline worktree's `.artifacts/accessor-bench-main-baseline/`; scaling source,
output and binaries remain in `.artifacts/accessor-scaling/`. Current metadata
identifies snapshot `31d00fb7` plus the documented integration worktree and exact
source/emitted-Go hashes; the accompanying final commit retains those changes.

## Review limits

Independent final implementation review remains outstanding. Host checks cannot
establish native behavior on macOS, Windows or the other supported architectures;
the repository's platform and distribution CI gates remain necessary. No PR,
merge, release or book publication is part of this change.

The aggregate `make verify-full` and a combined coverage run were not performed.
Its relevant native, race, fuzz, book and host-distribution components were run
separately as recorded above; this record does not claim complete CI coverage.
Contended-read performance remains unmeasured, although synchronization and
contended cancellation have behavioral and race coverage.
