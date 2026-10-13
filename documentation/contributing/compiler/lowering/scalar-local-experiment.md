+++
title = "Scalar local experiment"
weight = 3
+++

# Scalar local experiment

This bounded draft measures mutable uncaptured Int, Float and Bool local storage
against main `505b564e`. It changes neither the public ABI nor scalar arithmetic.
Only bindings with scalar operator assignments are selected. Checked binding
identity selects one native Go variable; immutable/ABI-only copies, captures, parameters,
generic locals, loop bindings and match payloads retain `Value` storage.
Locals initialized or assigned from a direct call also retain boxed storage.
This conservative eligibility rule avoids reboxing results at the next ABI call.

For example, the generated loop's declaration changes from
`var local7_total rt.Value = int64(0)` to
`var local7_total int64 = rt.IntValue(int64(0))`. Assignment changes from
`local7_total = rt.IntAdd(...)` to
`local7_total = rt.IntValue(rt.IntAdd(...))`. The same checked helper,
operand evaluation, `SourceAt` guard, cancellation checkpoint and source
directives remain. Go removes redundant local extraction without changing the
runtime boundary contracts. There is no second boxed storage slot.

## Measurements

Go 1.25.1, Linux amd64, Xeon Platinum 8573C, `GOMAXPROCS=1`, default GC,
unprofiled, three one-second samples per case. Each invocation executes 1,024
iterations through the real `Function.Body` ABI; checking, building and process
startup are excluded. Generated sources and logs are retained locally under
`.artifacts/scalar-locals/`.

| Case | Main allocations / bytes | Draft allocations / bytes | Initial main timing range | Initial draft timing range |
| --- | ---: | ---: | ---: | ---: |
| Int | 1,770 / 14,160 | 1 / 8 | 75.98–78.37 µs | 38.09–40.53 µs |
| Float | 1,793 / 14,344 | 1 / 8 | 69.05–71.16 µs | 32.80–35.43 µs |
| Bool | 769 / 6,152 | 0 / 0 | 46.58–58.72 µs | 32.31–32.47 µs |

A repeat under concurrent verification retained exactly the same allocations but
produced overlapping timing ranges and a slower Bool draft sample. These timings
do not establish a reliable speedup; quiet paired measurements remain necessary.
For this three-function fixture, Release size stayed 10,088,596 bytes; Debug
changed from 20,206,463 to 20,206,415 bytes. First builds had cold caches, so build
time differences are not attributed to the representation change.

The first all-local prototype regressed the existing source-call benchmark from
2,794 allocations / 46,928 bytes to 3,794 / 54,928 because its accumulator crossed
the `Value` ABI on each iteration. Retaining call-result storage removes that
regression: the bounded draft records 2,793 / 46,920. The existing list-access
benchmark recorded 3,818 / 96,080 on main versus 2,049 / 81,928 in the draft.
These are actual generated cases, separate from handwritten comparisons. Their
timings were collected under changing verification load and are not used for
a speedup claim. Current main `ecba349e` emits byte-identical scalar fixture Go
to the original measured `505b564e` baseline.

Independent review identified another real allocation regression in the broader
prototype: an immutable parameter copy repeatedly forwarded to a source call
reboxed on every iteration. Both Int (input 1,024) and Float (input 1.25) changed
from 1,024 allocations / 16,384 bytes to 2,048 / 24,576. Nongeneric identities
changed from zero allocations to one / 8 bytes. The final mutable-operator
eligibility rule retains these copies' original boxes; paired generated controls
again record 1,024 / 16,384 for forwarding and zero for both identities.
Primitive type information alone does not establish a useful storage optimization.

After #245/#248/#258 landed, the draft rebased cleanly onto main `bee671d4` and
repeated the generated forwarding/identity comparisons. The original three-loop
scalar fixture's generated main code remains byte-identical to its `505b564e`
baseline. Float parity also checks the repeated rounded loop and a typed-local
probe for separate-operation rounding, NaN, infinities, signed zero and subnormal
rounding, comparing exact bits for non-NaN results.

Reproduce current generated measurements with:

```sh
GOMAXPROCS=1 toolchain/go/bin/go run ./scripts/bench-lowering \
  -scalar-locals -count=3 -benchtime=1s
```

To reproduce the baseline, run the same source and harness against compiler main
`505b564e`; changing only a handwritten harness is not a production comparison.

## Contract evidence

Generated-form tests retain boxed captures and generic locals. Native tests cover
mutable reassignment, shadowing, closure snapshots, destructuring, boxed match
assignments, short circuiting, operand mutation order, checked argument
conversions, arithmetic faults and cleanup. The native debugger fixture inspects
and watches each scalar representation after assignments. The historical
pre-AST golden is restored byte for byte and hash protected; its old `TraceSource`
ABI is adapted only by the differential test at build time.

This is partial work for #87, separate from #142's typed-list storage. It makes no
one-second execution target claim and does not authorize merging representation
changes without review.
