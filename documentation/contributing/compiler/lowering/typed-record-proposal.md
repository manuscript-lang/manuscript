+++
title = "Typed record representation proposal"
weight = 5
+++

# Typed record representation proposal

This is a proposal/baseline artifact for #252, not a production implementation.
It is separate from #249's record concurrency policy and shares #251/#271's
authoritative checked-type and numeric representation mapping. Numeric and ABI
integration remains held for parent review.

## Preserve object identity first

Concrete source records can use generated Go structs referenced by pointers.
A copied binding must keep the same object; copying a struct value would change
ordinary record mutation and alias behavior. A shallow clone allocates a new
outer object and retains references to nested records, collections and handles.
It must not create clone permission for native resource handles.

Layout eligibility is keyed by checked record Type identity and concrete type
arguments, never the source type's spelling. Module-local type/implementation
identity, recursive references and generic instantiations participate. Start with
finite concrete source records and fallback for unresolved generic, native or
unsupported layouts. Field names use checked field identities and generated Go
identifiers; source names remain in metadata for diagnostics and debugging.

Scalar fields obtain Go types and box/unbox operations from #271's authoritative
mapping. Reference fields remain references. Optional/Result/interface fields
stay on their existing ABI initially. This proposal does not duplicate the
scalar map or infer a width from an old benchmark.

## One object across static and dynamic paths

Direct statically checked access can select a generated field. Generic/dynamic
field access, formatting, equality/hash, Error/interface views, clone and JSON
must adapt the same object; do not materialize an unsynchronized map mirror.
Adapters can expose a checked type key and field metadata plus getter/setter/
shallow-clone operations. Their boxed results preserve existing ABI boundaries.
An interface view and an unwrapped record must still refer to the same receiver.

Constructor adapters preserve supplied-argument order, checked conversions,
defaults and field initialization order. Default evaluation remains per
construction. A direct field assignment does not bypass source fault sites or
cleanup/resource lifetime checks. Closed or uncloneable native handles stay on
their current representation.

Concurrency is a distinct gate: generated fields must obey the accepted #249
policy and explicit Synchronized contract. A direct field must not silently
bypass protections that a dynamic adapter retains. This artifact implements no
lock elision or new synchronization semantics.

## Measured generated-program baseline

Main `c80bdb2a`, Go 1.25.1 Linux amd64/Xeon Platinum 8573C, GOMAXPROCS=1,
default GC, three one-second samples. These invoke actual generated Function.Body
entrypoints over 1,024 iterations, including wrappers, checked arithmetic,
source positions and cancellation. They do not compare map-backed records with
a handwritten struct after dropping language behavior.

| Generated case | Allocations | Bytes |
| --- | ---: | ---: |
| Construct 1,024 records retained in List | 3,854 | 434,560 |
| Mutate/read one record 1,024 times | 1,541 | 12,664 |
| Alias mutation plus 1,024 shallow clones | 11,985 | 800,728 |

Native parity checks length, final mutation and alias/clone behavior. Timings
vary heavily under shared load; the access samples ranged from 0.414 to 5.480 ms,
so no wall-time performance claim is made. These counts include scalar boxing,
collection storage and wrapper effects; they are not all attributable to record
maps. A useful typed-record experiment must repeat the complete generated cases
against the same runtime and widths, then include mixed generic/first-class,
view, formatting, equality/hash, JSON and clone controls.

The fixture and raw samples are retained in `scripts/bench-records`. Reproduce
the generated-program controls from the checkout root with the pinned SDK:

```sh
GOMAXPROCS=1 toolchain/go/bin/go run ./scripts/bench-records \
  -output .artifacts/record-bench -count 3 -benchtime 1s
```

The driver keeps the generated Go and its checked-symbol harness beside the
results. Its numeric expectations describe the measured historical 64-bit ABI;
they need deliberate migration with #271, not an inferred width change here.
Before integration,
measure actual retained heap/RSS and generated Release/Debug size as well as
allocation/time; padding, references, adapters and interface storage can dominate
field-width savings. #271 already owns the width-specific size measurements.

## Required evidence before implementation approval

Pair direct and dynamic access for mutable aliases, shallow/deep reference
boundaries, recursive/generic records, constructor defaults and conversions,
module-local views/equality/hash, clone restrictions, Error handling, JSON and
formatting. Include ordered field/receiver prerequisites, faults and cleanup,
cancelled delivery, cross-goroutine/race behavior under #249, source-level DAP
fields/watches, and all standalone distributions. The backend remains AST based.

This proposal does not authorize bypassing wrappers or locking based on
microbenchmarks. A separate reviewed implementation follows coherent #251/#271
ABI and type mapping decisions; no representation change is merged here.
