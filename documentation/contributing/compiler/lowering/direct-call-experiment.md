+++
title = "Direct call ABI experiment"
weight = 4
+++

# Direct call ABI experiment

This is a held design and test-only prototype for #251, based on main `e747d1e9`.
It does not change production lowering, select numeric widths, or add a second
scalar representation map. #271 owns signed32/binary32 defaults and explicit
wider types; current measurements preserve the preceding 64-bit ABI.

## Current baseline

Known nongeneric source calls already resolve supplied labels during checking and
use `Function.Body(ctx, []Value{...})` when all arguments are in declaration order.
They retain conversion-aware `argumentValue` and ordered `SourceAt` captures.
Dynamic functions, omitted defaults and reordered calls still use their existing
paths. Dropping `Invoke` everywhere is therefore not the current opportunity.

The existing generated 1,024-source-call loop records 2,794 allocations and
46,928 bytes per invocation on this main revision. Native checks, result parity,
wrappers, source positions and cancellation remain in the fixture. The existing
handwritten typed-local comparison records 3,795 allocations / 54,952 bytes:
unboxing and reboxing alone can worsen an ABI-heavy program. The old benchmark
template's `TraceSource` context signature was adapted only in the retained local
harness before these baseline measurements; compiler/runtime code was unchanged.

## Minimal candidate ABI

Eligibility is keyed by checked `*checker.Symbol` identity and its checked
parameter/result `*checker.Type` identities. Source spelling is not eligibility
evidence. Start with known nongeneric declarations, required scalar parameters,
all supplied arguments, and scalar results. Defaults, generic variables,
methods/interfaces and composite results retain existing wrappers until their
contracts are separately proven. Native Go types must come from the authoritative
#271 mapping; do not hardcode a competing Int/Float map.

Emit a native entry conceptually shaped as
`func symbolNative(ctx *Execution, left NativeInt, right NativeInt) NativeInt`.
Keep the existing first-class `Function` wrapper. Direct calls capture converted
arguments once in written order before invoking the native entry; native local
reads must not move after a later match or callback. The profile-enabled path can
use the existing wrapper initially. Wrapper bodies must not call back into that
fallback recursively.

The native entry retains cancellation admission and delivery, the same call-depth
limit, source-return handling, fault-frame defers and lexical cleanup ordering.
Result propagation must stop at its own Result boundary on supported composite
paths; primitive-only eligibility does not permit it to escape into a caller.
The experiment keeps depth accounting on every call. It does not establish that
recursion-only checks or statement-only source locations are equivalent.

## Test-only guard prototype

`pkg/runtime/native_call_experiment_test.go` explores a generic typed guard and a
handwritten typed add entry, using the runtime's existing cancellation, depth,
control-panic and trace machinery. It changes no production API. The private
generic test helper mirrors safety code to measure a candidate before deciding
how to share that code in production; it is not a proposed permanent duplicate.
Its profile-enabled entry falls back to the existing first-class wrapper.

On Go 1.25.1, Linux amd64, Xeon Platinum 8573C, `GOMAXPROCS=1`, default GC,
three one-second samples:

| Microcase | Allocations | Bytes | Raw timing range |
| --- | ---: | ---: | ---: |
| Prepared `Function.Body` add | 2 | 40 | 279.0–545.9 ns |
| Guarded typed add | 0 | 0 | 95.52–105.1 ns |

This isolates the calling convention and native result. It is not generated
production code, and its native-result sink differs from the Value sink by
design. Timings under shared load do not establish an application speedup.
The original generated loop remains the production baseline. A lowering
prototype must repeat its loop and real first-class-call controls before review.

Run the held microexperiment with:

```sh
GOMAXPROCS=1 toolchain/go/bin/go test ./pkg/runtime \
  -run TestNativeCallExperimentParity -bench BenchmarkNativeCallExperiment \
  -benchmem -benchtime=1s -count=3
```

## Regression obligations before lowering integration

Pair native and first-class calls for checked overflow/division/index faults,
precise source frames, written/reordered arguments and Optional/Error conversion,
short circuiting, defaults, capture snapshots and mutable callees. Cover normal
return, expression-match source returns, Result propagation, cancellation before
admission/during body/at delivery, cleanup before delivery, and recursion-limit
failure without leaked depth. Profiling on/off and native DAP must agree.

The current test prototype covers value/profile fallback, normal/source-return
cancellation, Result-boundary recovery, depth-limit admission, cleanup and fault
preservation. It does not yet prove arbitrary generated bodies, real deep
recursion, debugger stepping, acquisition disposal, distribution behavior or
code-size/build-time effects. Those remain gates for the later integration.

#259/#255 scalar integration remains held. #252 typed records stays queued until
the calling convention and numeric representation are coherent. Parent review
is required before broad implementation or merge.
