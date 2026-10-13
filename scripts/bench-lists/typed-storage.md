# Primitive storage, access and comparator evidence (#142)

Scope: authoritative Int64/Float64/Bool/String List backing, mutable identity,
relative indexing and Optional boundaries, wrapped comparator ABI, stable sorting,
construction and memory. #87 consumes typed scalar/access/call seams; #147 owns
large-literal emission; #166 owns public collection expansion and natural-sort
omission. Closed prototypes and the cancelled width migration are not dependencies.

| Contract | Evidence | Status |
| --- | --- | --- |
| One mutable identity across aliases/generics/saved methods | `TestPrimitiveListConstructorsAndAliases`, called primitive fixture | Implemented |
| Equality under user Equal mutating either operand | `TestListEqualityCapturesBothHeadersBeforeCallbacks`, native/standalone equality fixture | Both headers captured before length/traversal |
| Ordinary generated iteration and generic callbacks | Committed before/storage benchmarks and review ledger below | Regressions remain a combined #318 acceptance gate |
| Captured Go header, writes/growth/shrink/self-splice/retained tails | `TestPrimitiveListCapturedGoHeaders`, existing Go and source oracles | Implemented |
| Fresh construction and sized non-cancelling initialization | `TestFreshSizedListInitialization` | Two allocations for nonempty backing |
| Primitive Optional and fault/cancellation boundary | `TestPrimitiveListAccessAllocationsAndCancellation` | Zero typed read allocations |
| Guarded primitive comparator and ordinary Body | `TestTypedComparatorGuardParity`, stable/callable parity | One admission, depth/returns/profile/cancellation/frames |
| Natural order and Float NaN/infinity/signed zero | `TestPrimitiveNaturalSortAndFloatEdges` | Runtime seam; source omission owned by #166 |
| Source fast access and typed comparator emission | Generated workload below | #87 dependency; boxed reads regress |
| Large literal construction | Existing oracle unchanged | #147 consumes the pinned constructors |
| Strict Result slicing | Primitive native/standalone fixture | Preserved; negative bounds resolve, errors remain values |

Baseline binaries were built from main
`f01d88003284cc21ffda49284b04694c53f8cd8a` before edits, with bundled Go 1.25.1,
Linux amd64, AMD EPYC 9V74. Storage smoke binaries precede integration of structural
main `9d4e723d`; their JSON includes binary hashes and dirty provenance. Three
sequential samples are descriptive smoke evidence, not randomized paired speedup
claims. [Raw logs and JSON](results/typed-storage/) preserve allocation and RSS
observations. Native timings include startup; Go benchmarks exclude compilation.

| Fresh Release program | baseline median seconds / peak RSS | storage median seconds / peak RSS |
| --- | --- | --- |
| Append 1M Ints | 0.275 / 77.1 MiB | 0.214 / 36.2 MiB |
| Append 4M Ints | 0.648 / 284.2 MiB | 0.336 / 108.8 MiB |
| Build and stable-sort 200K | 0.873 / 29.3 MiB | 0.835 / 23.3 MiB |

1M/4M primitive memory workers use concrete locals and typed appends; each runs in
a fresh process, forces GC before construction and after retaining the list, and
checks kind/length/value. No element boxes or scalar-local artifacts are included.
String workers repeat one constant text value, so text payload storage is shared.

| Kind | 1M retained bytes | 4M retained bytes | 4M median allocations | 4M peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Int64 | 8,444,640 | 32,283,552 | 46 | 111.6 MiB |
| Float64 | 8,444,640 | 32,283,552 | 47 | 119.2 MiB |
| Bool | 1,112,704 | 4,315,872 | 40 | 26.4 MiB |
| String reference | 17,750,656 | 67,809,376 | 46 | 217.9 MiB |

The header is 144 bytes on this host, versus the old 40-byte boxed header. Int/Float
backing is 8 bytes per reserved element, Bool 1, String 16. Append capacity differs
by element layout; old arrays and GC headroom explain RSS beyond retained storage.
The matched boxed 4M runtime baseline retained 99,722,304 bytes; generated source
retained 131,638,080 bytes. The primitive workers retain about 32.3 MB for 4M Ints.

`BenchmarkPrimitiveList` (65,536 values, three 100ms samples) measures the production
runtime seams: fresh copy 2 allocations / 524,433 bytes; typed at/unwrap 0 bytes /
0 allocations; fully wrapped typed stable sort 4 allocations / 524,488 bytes and
about 42–45ms. These are runtime controls, not a claimed compiler speedup.

The generated workload deliberately still uses current source lowering. Append
falls from 6,585,540 to 3,557,560 allocated bytes at the same 130,681 allocations;
scalar-local boxing remains #87's scope. Boxed at/unwrap rises from 327,424 to
392,795 allocations (one new payload box per non-small primitive read). Typed
source lowering must consume `ListAt*` before combined acceptance. Generic stable
sorting boxes once per element, with 2,291,172 versus 2,225,800 allocations, instead
of the earlier per-comparison storage prototype's 2.26x regression. Fully typed
comparators avoid both the working boxed array and per-comparison payload boxes.

## Review correction: traversal allocation regressions

The original acceptance summary omitted two regressions visible in the committed
raw samples. At 65,536 Ints, the ordinary generated paths measure:

| Path | baseline allocations / bytes | storage allocations / bytes | Required combined acceptance |
| --- | ---: | ---: | --- |
| `for` iteration | 65,535 / 524,284 | 130,912 / 1,047,504 | Measure actual emitted traversal after #318, including header adapter overhead |
| Generic `for_each` callback | 131,090 / 1,574,029 | 196,461 / 2,097,057 | Measure ordinary boxed callbacks as well as typed callback fast paths |
| Boxed backing, concrete accumulation local | 1 / 8 | 5 / 216 | Account for iterator function/capture overhead independent of primitive payload boxing |

The callback increase is exactly 65,371 allocations: the non-small Int payloads
boxed at the generic callback boundary. Iteration adds those payload boxes plus
constant iterator/capture allocations. These explanations follow the stored code
and allocation counts; they are not a profile-backed timing attribution. Smoke
iteration times also increased, but the sequential samples do not establish a
paired confidence estimate. Typed `CaptureList` loops and comparator controls
cannot stand in for these ordinary paths. Combined #318 acceptance must rerun
append/index/iteration/callback/sorting and compare allocations and bytes against
the labeled baseline; memory savings alone do not clear these regressions.

The equality review found a separate semantic bug: reloading live List headers
let an element's user Equal shrink/extend membership or switch arrays on growth.
Capturing both headers before length/traversal restores ordinary Go slice behavior
without cloning backing. Independent Go and called source tests exercise both
operands, shrink (including skipped mismatches), append with spare capacity,
reallocation, and visible replacement of an unvisited backing cell.

Reproduce with the current Makefile and writable caches:

```sh
make payload
toolchain/go/bin/go run ./scripts/bench-lists -output .artifacts/list-bench -count 3
toolchain/go/bin/go test ./pkg/runtime -run 'TestPrimitive|TestFreshSized|TestTypedComparator' \
  -bench '^BenchmarkPrimitiveList$' -benchmem -count 3
make build
python3 scripts/bench-lists/native.py --cli ./ms --output .artifacts/list-native --runs 3
toolchain/go/bin/go test -c -o /tmp/primitive-lists.test ./pkg/runtime
MS_PRIMITIVE_COUNT=4000000 MS_PRIMITIVE_KIND=Float /tmp/primitive-lists.test \
  -test.run='^TestPrimitiveListMemory$' -test.v
```

Use Int, Float, Bool or String for the memory kind. Run each repetition in a fresh
process and obtain peak RSS through `wait4` or an external process accounting tool.
Copied standalone native consumers and the moved `pkg/build` tests belong in final
combined-tree validation. Do not close #142 on storage-only evidence while source
access/comparator and literal consumers remain unresolved.
