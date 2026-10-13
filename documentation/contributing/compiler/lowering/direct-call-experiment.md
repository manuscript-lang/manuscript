+++
title = "Direct call ABI experiment"
weight = 4
+++

# Direct call ABI experiment

This is the held #251 generated pilot, based on main `c80bdb2a`. It is enabled
only by `compiler.Options.ExperimentalNativeCalls`; the ordinary compiler and
CLI keep their existing lowering. Runtime source adapters now share one guard
on this experimental branch. This is not an approved production ABI or merge.
#271 owns signed32/binary32 defaults and explicit wider types; these measurements
preserve the historical 64-bit ABI. #259/#255 integration remains held.

## Checked eligibility and boundaries

Known nongeneric source calls already resolve supplied labels during checking
and use `Function.Body(ctx, []Value{...})` for fully supplied ordered arguments.
The opportunity is the remaining Value array, boxing and indirect-call boundary.
Dropping `Invoke` everywhere is not the current baseline.

The pilot selects declarations by checked `*checker.Symbol` and parameter/result
`*checker.Type` identities. It reuses `primitiveEqualityType`, the existing
checked scalar Go-type mapping, and derives assertions from that mapping. There
is no second width/box map. The #271 owner must supply/update its authoritative
mapping before integration. Explicit wide types remain boxed in this pilot.

Only nongeneric, required scalar signatures and fully supplied arguments in
declaration order use a native call. Dynamic/first-class calls, generic/defaulted
signatures, reordered arguments, methods/interfaces and composite results keep
their Value ABI. Optional/Error conversion still uses `argumentValue` on those
paths. Direct arguments are converted and captured once in explicit statements
in written order, with `SourceAt` before the next argument and the final call.
A local read cannot move past a later match or callback mutation.

There is a further conservative result-use gate: native bodies must produce a
scalar rather than forward an already boxed binding. Identity, local/payload-only
returns and forwarding chains ending in those returns stay boxed. Otherwise the
first-class adapter would unbox and allocate a replacement box. Forwarding a
computed native result can remain native. Eligibility is pruned to a fixed
point; unsupported nested callable/return shapes fall back conservatively.
This is a held use classification, not a new language rule or typed IR.

## One body and one source guard

`lower_native_calls.go` builds three AST components for an eligible declaration:
an unguarded typed body, a guarded native entry and a first-class boxed adapter.
`functionParts` and the existing statement/expression builders lower the body;
its native parameters are keyed by checked binding identities. Local storage
remains Value. Nested source closures save their own Value ABI and cleanup state.
The typed body owns its position variable, trace defer and lexical cleanup.

```text
known ordered call -> native entry -> SourceCall -> typed body
first-class call   -> boxed adapter -> SourceCall -> typed body
profile boundary   -> selected adapter -> SourceCall -> attribution -> typed body
```

`SourceCall` owns cancellation admission/delivery, every-call depth, source
returns and Result recovery. `NewSourceFunction`, `SourceDirect` and `BoundDirect`
select that guard once; a wrapper never guards an already guarded native entry.
The temporary mirrored test guard has been removed. Native/profile adapters do
not fall back into the same wrapper. Generic/default/composite callers still
stop propagation at their own Result boundary.

Attribution runs inside the selected guard. Adapter selection checks the existing
inherited source-profile boundary; nested calls retain #234's sampled-stack path
without new labels/regions. A collector callback must not make the normal body
thunk escape. Generated importers initially exposed an additional 48-byte thunk
per boxed call that a package-local microbenchmark missed. Keeping the boxed
constructors out of cross-package inlining preserves the guard's no-escape fact.
The actual generated identity control now remains allocation-free.

## Generated-program measurements

Same candidate runtime, Go 1.25.1 Linux amd64/Xeon Platinum 8573C, GOMAXPROCS=1,
default GC, three one-second samples. Baseline disables only the pilot option;
wrappers, source positions, checked arithmetic and cancellation remain. The
1,024-call result is 523,776 in both modes.

| Actual generated case | Baseline allocations / bytes | Pilot allocations / bytes |
| --- | ---: | ---: |
| 1,024 known source calls | 2,794 / 46,928 | 1,770 / 14,160 |
| 1,024 mixed first-class calls | 2,794 / 46,928 | 2,794 / 46,928 |
| Boxed identity | 0 / 0 | 0 / 0 |
| Boxed forwarding to identity | 1 / 16 | 1 / 16 |
| Boxed forwarding to computed add | 2 / 40 | 1 / 8 |
| Boxed add | 1 / 8 | 1 / 8 |

Raw samples are in `scripts/bench-lowering/testdata/native-call-pilot.*.samples.txt`.
Shared-host timings do not establish a general application speedup. Binary size,
retained heap/RSS and profile overhead need separate controls; allocation counts
alone do not settle those costs. A two-function artifact with the same source
root compared original main `c80bdb2a` with the candidate runtime plus pilot:
Release grew from 5,554,360 to 5,558,456 bytes (+4,096), and Debug from 11,186,594
to 11,207,488 (+20,894). This is a small fixture, not a large-application estimate.
Uncontrolled build elapsed times were 5.86/5.28 seconds (Release/Debug baseline)
and 10.17/1.77 (pilot); unequal caches and shared load prevent attributing a
compile-time regression or improvement. Raw observations are retained beside
the allocation samples. A controlled cold/warm build comparison remains a gate.

```sh
GOMAXPROCS=1 toolchain/go/bin/go run ./scripts/bench-lowering \
  -native-calls -baseline -output .artifacts/call-baseline -count 3 -benchtime 1s
GOMAXPROCS=1 toolchain/go/bin/go run ./scripts/bench-lowering \
  -native-calls -output .artifacts/call-pilot -count 3 -benchtime 1s
```

The harness retains generated Go, checks results and includes a cross-package
allocation assertion for boxed identity. The preceding handwritten guard samples
remain in `native-call-experiment.samples.txt`; they are historical microcases,
not the generated-program comparison. The original historical e747d1e9 generated
baseline was also 2,794 / 46,928. Its handwritten typed-local comparison was
3,795 / 54,952, reinforcing the need to measure ABI boundaries.

## Validation and remaining integration gates

Runtime tests pair native/boxed/direct/bound adapters, profiling on/off, exactly
one depth/admission/delivery, cancelled admission without body entry, normal and
source-return cancellation, Result recovery, exact overflow frame parity, boxed
nil returns, ordinary fault preservation and cleanup. Actual 200,000-call native
and boxed recursion faults and restores the execution's depth. The generated pilot tests
Release/Debug values, ordered arguments, match source returns, short circuiting,
reordered fallback, cleanup, recursive calls, IEEE per-operation rounding and
complete fault/frame equality against boxed lowering, including CPU/trace modes.
Output determinism and conservative eligibility are checked separately.

The retained prebuilt native DAP fixture uses normal build metadata and inspection.
It checks source stepping, the source frame, native parameters, local values and
watch expressions. Synthetic position writes in the new native body map to the
upcoming statement; inheriting physical Go offsets from a previous directive
otherwise yields a misleading step location. That issue was also reproduced in
boxed baseline lowering; its broader correction is left for the later handoff.

```sh
toolchain/go/bin/go run ./scripts/bench-lowering -native-calls -debug-fixture \
  -output .artifacts/call-dap
toolchain/go/bin/go build -o .artifacts/ms ./cmd/ms
MANUSCRIPT_MS="$PWD/.artifacts/ms" \
MANUSCRIPT_NATIVE_CALL_FIXTURE="$PWD/.artifacts/call-dap" \
  node --test extensions/vscode/tests/native-call-pilot.test.js
```

The compiler pilot option remains off in CLI-created artifacts. The explicit DAP
fixture avoids adding a supported experimental CLI flag. Before integration,
repeat the complete evidence after #271's coherent width/host transition and
parent review. Wider/generic/default/composite eligibility, native acquisitions,
#252 record representation and #259 scalar storage are excluded here.

## Layer handoff

Checked call/result eligibility belongs in `lower_native_calls.go`; callable
syntax belongs in `lower_functions.go`/`lower_statements.go`; execution safety
belongs in `pkg/runtime/values.go`; collector policy belongs in `profile.go`;
serialization remains the existing Go AST printer boundary. `values.go` also
owns records, invocation, registration, method caches and fault tracing: its
1,295 lines expose module pressure for the later consolidation. The common
source guard removes one real duplication without beginning that broad split.
Runtime acquisition guards in `newFunction` have a separate disposal contract.
Synthetic source-position writes and source statement mapping currently split
ownership between `lower_statements.go` and the AST printer; the baseline step
misattribution above is concrete evidence for consolidating that ownership later.

`skills/manuscript-change`, the domain skills and `.experts/language.md`,
`runtime.md`, `tooling-and-docs.md` repeat guidance about checked identities,
ordering, cleanup and source maps. The later skill/expert consolidation should
keep concise routing in skills, canonical rules in documentation and measured
failure mechanisms in experts. No broader reorganization is performed here.
