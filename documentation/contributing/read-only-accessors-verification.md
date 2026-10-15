+++
title = "Read-only accessor implementation evidence"
weight = 28
+++

# Read-only accessor implementation evidence

The implementation follows the [approved design](read-only-accessors-design.md).
The feature and its review corrections have independent code-review approval.
The user authorized pushing the branch and opening a draft PR; merge remains held.
The parent relayed explicit independent approval of design commit
`46c46a29105e1aabb969d22cce96825b52dc0b8a` before implementation began.

Post-publication #520 fixture migration and primitive-literal composition are recorded in
`scripts/bench-accessors/results/verification/main-integration-cd381fc4.md`.
The preceding #519 fixture migration and generic-record composition are recorded in
`scripts/bench-accessors/results/verification/main-integration-bb450ff0.md`.
The preceding #518 composition and conflict resolution are recorded in
`scripts/bench-accessors/results/verification/main-integration-967e9127.md`.
The preceding #517 composition, the boxed List fallback correction, and its
fresh checks are recorded in
`scripts/bench-accessors/results/verification/main-integration-d70b29be.md`.
Pre-publication main #513–#515 integration is recorded in
`scripts/bench-accessors/results/verification/prepublication-main-b2a288b1.md`.
The preceding integrated checks and measured guard/Logger evidence are recorded
in `scripts/bench-accessors/results/verification/main-integration-9dcc0bae.md`.
The original measurements and coverage below remain historical evidence for
their stated revisions.

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

## Independent final review

A fresh reviewer inspected exact feature commit
`5107114ece3d72beb8ebfef9e1cdd5d1858b1dac` against the approved design and base
`1383851ebb24d2dc8a0a13d8cec0021bf32e833d` in an immutable detached worktree.
The judgment was **APPROVE with one nonblocking P3 correction**. This was an
independent reviewer judgment, not approval by the implementation author.

The proven finding was `pkg/checker/hints.go:408`: an Optional type-error remedy
still recommended `is_some()` before `unwrap()`. Following that advice caused
another accessor-call error. Correction commit
`12a26d19687f371c18d11cdf1db1b7b35720bc71` changes the remedy to `is_some before
unwrap()` and pins it in the three existing Optional diagnostic cases. This is
the only production-code change after the reviewed feature snapshot.

The same independent reviewer re-reviewed the complete two-file correction and
returned **APPROVE**, with no new finding. The reviewer ran focused tests across
eight packages, an additional native generic Result/function-valued-accessor
ordering probe, the diagnostic correction test, a direct diagnostic repro and
whitespace checks. Full review and re-review reports are preserved unchanged in
`scripts/bench-accessors/results/verification/`.

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
| Native build suite | The full `pkg/build` suite passes after #503 integration, including the final combined run at exact `12a26d19` (196.168 s). All four accessor native integration cases cover source scopes, standard-contract implementations, fault frames, depth and cancellation. |
| End-to-end suite | Complete fresh post-format suites pass at `5107114e` (288.394 s) and `12a26d19` (290.146 s and final 297.664 s). The earlier formatting failure is fixed; these later results are whole-suite passes. |
| Combined coverage | The final clean all-package run at `12a26d19` passes all 32 packages, with 5,554 passing test/subtest events, two intentional skips, no failures and 78.0% combined statement coverage. Function and HTML reports generate successfully. |
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

The harness and reproduction commands live in `scripts/bench-accessors/` in this
checkout.
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
All nine original result files remain byte-identical to `5107114e`, verified by
`results/verification/raw-measurement-manifest.json`. A generation-only check at
reviewed correction `12a26d19` reproduces the measured source and emitted-Go
hashes; the emitted-Go SHA-256 is
`1a197b745aad18a9c532997ad36b5aad899d4be66e091ea3b2b138ce6de1af55`.
That check generates no new timing samples.

## Complete e2e and combined coverage follow-up

The entire e2e suite passed after the formatting correction: **288.394 s** at
`5107114e`, then **290.146 s** and a final **297.664 s** at the independently
reviewed correction `12a26d19`. These were complete fresh suites, not selections
of previously failing tests. Their Go JSON logs remain in
`.artifacts/verification/`.

Two aggregate attempts exposed local test-environment issues, retained in the
record rather than reported as passes:

1. The initial manual command omitted Makefile's pinned-SDK PATH. Eleven packages
   without tests could not generate their coverage reports because a bare `go
   tool` reached the unrelated system executable. All test-bearing packages,
   including the complete e2e suite, passed, but the command exited 1.
2. The next command used the pinned SDK. Five LSP rename tests discovered the
   deliberately invalid reviewer probe `/tmp/accessor-optional-hint.ms` and
   correctly rejected rename in an invalid workspace. The probe and the valid
   native probe were archived under hidden `.artifacts/verification/review-probes/`;
   the full clean LSP retry passed in 6.691 s. The e2e suite again passed, but the
   aggregate command exited 1.

A local test-execution wrapper also preserves `-buildvcs=false` for debugger
helper builds whose own GOFLAGS override the outer environment. With that setup,
the full native debugger Go suite executes with **zero skips** and passes in
6.189 s. No debugger production code or CI workflow was changed for this repair.

The final combined run uses the same all-package, atomic-coverage and
native-example inputs as `make coverage`, with a fresh count, package concurrency
2 and a 30-minute package timeout. Pinned SDK PATH and the test-execution wrapper
are environment accommodations, not test filters. The command is:

```sh
MANUSCRIPT_EXAMPLES_NATIVE=1 toolchain/go/bin/go test \
  -exec /tmp/manuscript-accessor-native-go/test-env \
  -json -timeout 30m -count=1 -covermode=atomic \
  -coverpkg="$(toolchain/go/bin/go list ./... | paste -sd, -)" \
  -coverprofile=.artifacts/coverage/coverage.out ./...
toolchain/go/bin/go tool cover -func=.artifacts/coverage/coverage.out
toolchain/go/bin/go tool cover -html=.artifacts/coverage/coverage.out \
  -o .artifacts/coverage/index.html
```

The wrapper puts a temporary `go` shim first on each test process's PATH. The
shim delegates to this pinned SDK, adding only `-buildvcs=false` to helper `build`
commands. The outer coverage command uses `GOFLAGS='-buildvcs=false -p=2'`.
The final command exits **0**. All **32 packages pass**, including `pkg/build`
(196.168 s), `tests/examples` (11.604 s), `pkg/tooling/lsp` (35.956 s) and the
complete `tests/e2e` (297.664 s). The JSON stream contains **5,554 passing
test/subtest events**, **zero failures or build failures**, and exactly two
intentional skips: `TestPrimitiveListMemory` requires an opt-in fresh-process
memory worker; `FuzzCSVRoundTrip/seed#3` intentionally excludes its CRLF input.
The native debugger tests have no skips.

Combined statement coverage is **78.0%**. Both `go tool cover` commands succeed,
producing `.artifacts/coverage/functions.txt` and
`.artifacts/coverage/index.html`. The final profile is
`.artifacts/coverage/coverage.out` (SHA-256
`f7d8f01c98fe422f05f2fe96ea7268f7b2fe07594802ef293d3362ac9677dc7a`).
The complete JSON log is
`.artifacts/verification/coverage-12a26d19-final.jsonl` (SHA-256
`5b78f1105015628423aaa729cd9949d26be15e8baca749bf75b661ce66ffb4b9`);
its stderr log is empty. Machine-readable counts, package outcomes and artifact
hashes are saved in `scripts/bench-accessors/results/verification/coverage-summary.json`.

## Semantic acceptance coverage

- Receiver-once evaluation, repeated live reads, mutation between reads, skipped
  short-circuit reads and side-effecting source getters are exercised natively.
- Assignment rejection, field/member collisions, accessor-versus-method contract
  conformance, visibility, partial syntax, safe old-call edits and callable
  results are checked. A getter result of function type is read before ordinary
  function-call arguments execute.
- List first/last and queue peeks preserve absence, nested Optional values and
  mutable payload aliases. ClientResponse metadata follows replacement of its
  existing head while earlier aliases remain attached to the old head.
- Concrete source implementations, explicit interface views, generic bounds,
  generic Result propagation, two module-local implementation scopes, and source
  implementations of standard Directory/ResponseBody contracts execute correctly.
- Executing reads participate in effects, try-order barriers and recursive call
  graphs. Source fault lines, sampled depth/cancellation, native admission and
  delivery boundaries, and Int's existing no-checkpoint exception have regressions.
- Guard reads retain holder validation and mutex synchronization, including stale
  and closed guards and cancellation during a contended read. Resource metadata
  retains each prior post-close contract; a retained value adds no resource lease.
- Error.message and every discovered standard implementation remain methods.
  Concrete/view/generic invocation, deferred method values, side-effect counts and
  verbatim native Failed text are explicit non-regressions. Retained action,
  conversion, snapshot and unlisted getter controls remain callable.
- Property completion, result-value hover, references/rename/navigation, LF/CRLF
  and Unicode positions, immutable standard documents, JSON format 2 and source
  getter breakpoints are covered. Debugger field expansion and ordinary record
  watches do not execute getters.
- Emitted-Go checks reject bound-callable construction and Invoke/Bind/CallNative
  in all 20 statically resolved core reads. Typed scalar/tag representations and
  one annotated syntax tree remain in use; native fields are not getter snapshots.

## Supported-platform checks

The affected `pkg/runtime`, `pkg/checker` and `pkg/lower` packages cross-compile
successfully at `12a26d19` for Linux/arm64, Darwin/amd64, Darwin/arm64,
Windows/amd64 and Windows/arm64, with CGO disabled and the existing
`exp.winarm64` tag. These are source-compilation checks, not execution or complete
distribution-package verification. Linux/amd64 native and standalone execution
already pass locally.

The checks that genuinely need other native runners here are:

- Linux/arm64 standalone compilation, LSP, terminal/DAP debugging, profiles and
  resource behavior using the bundled target SDK.
- Darwin/amd64 and Darwin/arm64 native filesystem, watcher, path, signal/process,
  networking and standalone behavior; debugger execution also needs Apple's
  debugserver environment.
- Windows/amd64 and Windows/arm64 native paths, filesystem/watchers, process and
  signal/shutdown behavior, networking, target SDK and DAP behavior. Windows ARM64
  must exercise the enabled native Delve backend, not just accept its build tag.

`.github/workflows/release.yml` packages all six supported triples, then runs
standalone verifiers on their native runners. `.github/workflows/test-language.yml`
also runs the selected macOS/Windows host-compatibility cases. Cross-building can
be done here; those native executions cannot. No QEMU or Wine is available, and
neither would establish native macOS/debugserver behavior. CI cannot be triggered
for this unpublished local commit without a separate publication action.

## Review limits

Independent code review and exact correction re-review are complete. Host checks cannot
establish native behavior on macOS, Windows or the other supported architectures;
the repository's platform and distribution CI gates remain necessary. No PR,
merge, release or book publication is part of this change.

The aggregate `make verify-full` was not invoked as one command. Its relevant native, race, fuzz, book and host-distribution components were exercised separately; the final combined-coverage status is recorded above. This record does not claim complete cross-platform CI coverage.
Contended-read performance remains unmeasured, although synchronization and
contended cancellation have behavioral and race coverage.

## Saved review materials

The canonical design remains
`documentation/contributing/read-only-accessors-design.md`. This verification
record and both unchanged independent review reports are also preserved as
numbered UTF-8 text chunks in
`scripts/bench-accessors/results/verification/chunks/`. Each complete chunk is
smaller than 6,000 characters and bytes. `chunks/manifest.json` records their
order, source hashes, sizes and reconstruction hash. The nine raw performance
result files remain unchanged; the delivery copy also includes the final coverage
profile, function report, HTML report and complete Go JSON log.
