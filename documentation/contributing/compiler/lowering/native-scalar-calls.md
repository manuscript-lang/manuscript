+++
title = "Native scalar storage and calls"
weight = 4
+++

# Native scalar storage and calls

The checker retains binding, type and declaration identities. Lowering uses those
identities to keep concrete `Int`, `Float`, `Bool` and `String` values in native Go
storage where their uses permit it. `Int` remains signed 64-bit and `Float` remains
binary64. There is no source syntax or default-width migration.

## Storage and callable boundaries

Arithmetic accumulators and immutable computed values consumed by native
operations use one typed local. Captures and existing boxed payload copies retain
their shared value boundary. A typed local has no boxed mirror. Passing a value to
a generic operation, storing it in a dynamic aggregate, or capturing it converts
at that boundary. Choosing storage by the spelling of a source name is unsafe:
shadowed locals and same-named nominal types retain their checked identities.

Known nongeneric source declarations have an unguarded body and a guarded native
entry. Their primitive parameters and results use Go scalar types; other values
retain `runtime.Value`. Fully supplied, reordered and omitted-default calls can
use this entry. Supplied arguments are captured in written order. Presence flags
let the callee evaluate omitted defaults after admission, in declaration order,
with earlier parameters available. Explicit arguments skip their defaults.

The ordinary first-class `Function.Body` remains available. It shares the typed
body only when unboxing its inputs does not introduce replacement boxes for
identity returns, forwarding, captures or storage. Other adapters lower the same
checked body with boxed parameters. This preserves existing input boxes instead
of keeping parallel native and boxed local storage. Generic and dynamic calls
retain their callable preparation and selected implementation scopes.

## One source boundary

`runtime.SourceCall` owns source admission, call-depth accounting, source returns,
Result propagation and delivery cancellation. Both native entries and boxed
source adapters select this boundary once. `ProfileSourceCall` performs attribution
inside the same boundary, retaining execution accounting and inherited profile
regions. The body owns source tracing and lexical cleanup. Native resource
acquisitions keep their separate disposal contract.

Source methods use the same guard. Generated registrations mark their direct
entry as guarded; raw Go direct registrations receive router admission during
registration. Binding a guarded source method does not add another guard.
Recursion is charged on every source call and a depth fault unwinds the charge.

Pure scalar operations emit direct Go expressions. If a later operand can mutate
an earlier local, lowering captures both operands before operating. Each checked
arithmetic operation sets its fault site after evaluating operands and before
performing the operation. Integer overflow and division faults remain checked;
Float operations retain binary64 rounding at each source operation. The source
position update and executable statement both map to the upcoming source line.

Resolved `math.sqrt`, `abs`, `floor`, `ceil`, and primitive `Int.to_float` calls
use typed native helpers with ordinary native admission and delivery. Native
helpers add no source frame or source-call depth. Bound methods and first-class
native references retain their callable ABI; an application function named
`sqrt` does not acquire native behavior.

## Validate the whole workload

Run the pinned SDK from the repository root:

```sh
toolchain/go/bin/go run ./scripts/bench-lowering -workloads -count=5
```

This retains actual generated source and compares loops, known calls,
`List.at(...).unwrap()` and 128×128 Game of Life for 50 generations with
handwritten Go. It checks the same deterministic results and includes boxed
identity, forwarding, copying, closure-capture and storage controls. Each sample
reports time, bytes and allocations. Build and startup time are outside this
harness; native CLI and distribution checks exercise those paths separately.
Handwritten Go is a workload reference and omits Manuscript fault, cancellation
and source-call accounting. The older `-production` and default harnesses isolate
specific lowering choices with more runtime guarantees retained.

Compare a fresh main checkout and the candidate with the same SDK, sources,
benchmark arguments and host. Retain both generated artifacts, exact commits and
raw samples. Shared-host timings are observations; allocation counts and result
parity are separate acceptance evidence. A loop microbenchmark does not settle
collection access, typed sorting or Game of Life acceptance.

The independent pre-AST executable oracle remains hash protected in
`pkg/build/testdata/go-ast`. Its source bodies retain complete target transitions;
a native body can specialize fully supplied defaults, while its boxed adapter
retains their full mapping. Printer marker accounting still requires each emitted
marker exactly once. Native conformance, IEEE/fault/cancellation tests, deep
unwind, Debug stepping and offline copied-toolchain checks validate the runtime
and debugger contracts beyond emitted AST shape.

## Compatibility

Manuscript source signatures and numeric defaults are unchanged. Rebuild native
artifacts and exported generated Go with the matching compiler/runtime pair;
implementation pins invalidate cached artifacts. Generated code now uses
additional runtime entry points. Go consumers constructing `Implementation`
should use keyed fields because the additive `DirectGuarded` field changes
unkeyed composite literals. Hand-authored source callbacks can keep using
`NewSourceFunction`, and ordinary native callbacks keep using `NewFunction`.

The signal and diagnostic-output goroutines do not execute source code or touch
user record fields, so they do not enable record locking. Task groups,
schedulers, servers and watchers still mark concurrency before source work is
spawned. Records retain their existing layout and shallow-clone behavior.
