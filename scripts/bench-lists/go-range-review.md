# List traversal without copies

The user's explicit follow-on direction supersedes #247's List snapshot/COW
contract. List loops and callbacks capture the backing slice and initial length
once. In-place writes can change later reads; append cannot extend traversal;
reallocation leaves traversal reading its original array. The List-only shared
flag, snapshot header, callback argument copy and writer detach calls are removed.
Production storage remains `Items []Value` on the authoritative `*List` handle.

Map/Set snapshots, explicit clone/slice/sorted-result storage, shallow nested
references, closure capture and synchronization requirements keep their contracts.
Self-splice still stages its replacement locally to preserve replacement behavior.
Removal and shrinking splice use non-clearing Go shift-and-reslice semantics.
Captured ranges can visit shifted/repeated prior values, including the vacated
tail. Full splice-to-empty reslices the receiver to zero while retaining backing
capacity. Removed references can remain retained until overwritten, reallocated
or released. No typed zero-value policy or numeric-width migration is introduced.

## Non-clearing shrink

The earlier draft was held despite green gates on `d8a83a2a`: its Go `[]Value`
oracle observed nil after removal and native shrink ignored the binding.
Consuming that cell as source Int instead reproduced
`interface conversion: interface {} is nil, not int64`, exit 70, with no source
frame. [Source](repro-cleared-tail.ms) and [raw reproduction](results/go-range/cleared-tail-repro.json)
are retained as historical failure evidence. Parent approved non-clearing shrinking
mutations in the current boxed representation, preserving valid prior tail values
without snapshots, traversal copies or invented zero values. The source now checks
the Go-equivalent sum 7 (`[1, 3, 3]`) and succeeds. Run it with the candidate's CLI:

```sh
./ms run scripts/bench-lists/repro-cleared-tail.ms
```

Consumer-level native/standalone tests exercise Int, Float, String, records,
alternatives and nested Lists through generic functions, stored callbacks, map
and left/right folds. Runtime tests consume concrete typed values and compare
independent ordinary Go append/reslice oracles, including full clear, append reuse
and external Go header reset. Explicit clones remain independent; retained nested
references stay shallow. Cancellation and exact source-frame checks now mutate by
removal and full splice-to-empty. No other existing mutator return/bounds contract
requires a change; there is currently no public List.clear method.

Integrated main through `a590954d` includes #263 preferred aliases. Called source
consumers now dispatch interface views after shrink and exercise stored `set`,
`remove`, `reverse_in_place`, and independent shallow `reversed` results. Independent
search tests capture the current value before predicates mutate its cell: forward
and reverse `find` return that same shallow matching value, and index variants keep
the captured index. This fixes the review's post-predicate reload bug without any
copy/COW. The prior 13-callback Body-versus-dispatch comparison shared that bug;
new tests use explicit expected values and ordinary Go mutation oracles instead.

Main's accepted String and duration-site changes were subsequently integrated;
the completed `d8a83a2a` gates are evidence for that precise head, not a later head.

## Semantic evidence

`pkg/runtime/list_range_test.go` compares runtime traversal against independent
ordinary Go slice mutations, with and without spare capacity: replacement, fill,
reverse, prepend, removal, overlapping/truncated copy, append followed by a prefix
write, shrink, and self-splice. Nested ranges and all 13 List callback algorithms
retain the captured backing. Callback faults and cancellation retain early exit
and mutation; native tests assert exact source frames and cancellation identity.

The called native and standalone `list-go-range.ms` fixture exercises aliases,
bound/generic callbacks, fixed initial length under growth/shrink, nested ranges,
shallow clone/slice storage, recursive values and function-value replacement.
The empty callback boundary and header capture assert zero allocations and no
receiver-header mutation. Header capture alone reports 0 B/op and 0 allocs/op in
three bundled-Go benchmark repetitions.

## Paired normal-GC evidence

Before: main `1634262f`, after: integrated head `5d18e41e` plus declaration-comment
and generated API documentation edits. Runtime/lowering was clean when binaries
were built. Both contain #269's complete callback set. The generated program and
benchmark harness are byte-identical; source and binary SHA-256 hashes are in
[provenance](results/go-range/provenance.json). Bundled Go 1.25.1, Linux amd64,
Intel Xeon Platinum 8573C; CPU 0, GOMAXPROCS=1, GOGC=100, no GOMEMLIMIT.

Each timed generated-source call gets a fresh shallow clone of the same prebuilt
65,536-element list. That common 1 MiB clone is included on both sides. The write
callback replaces index 0 after reading it, so these workloads have the same
checksum under both contracts. Mutation visibility is tested separately above.
Compilation and startup are excluded. Twelve pairs use fixed-seed random order,
200ms per case; ratios are geometric means, with 10,000-resample paired bootstrap
intervals. The stable benchmark name `BenchmarkNarrowSnapshots` is retained for
comparison with the historical binary; it does not describe the new semantics.

| Case | after/before time | paired 95% interval | median bytes before / after | allocations before / after |
| --- | ---: | --- | ---: | ---: |
| Read-only callback | 0.977 | 0.962–0.990 | 2,622,749 / 2,622,670 | 131,095 / 131,093 |
| Write inside callback | 0.879 | 0.818–0.926 | 3,672,037 / 2,623,380 | 131,107 / 131,104 |
| First write after callback | 0.892 | 0.867–0.910 | 3,671,788 / 2,623,130 | 131,109 / 131,106 |

The writing cases remove the approximately 1 MiB deferred backing copy and three
allocations; read-only capture removes about 80 bytes and two allocations. All
12 writing pairs and 9/12 read-only pairs were faster on this host. Raw trials and
[paired results](results/go-range/results.json) are retained. These timings do
not establish universal speedups, and callback/boxed-scalar overhead still exists.

```sh
python3 scripts/bench-lists/normal_pairs.py \
  --before /path/to/before.test --after /path/to/after.test \
  --output .artifacts/range-pairs --count 12 --cpu 0 --benchtime 200ms
```

This bounded slice leaves #142/#87 open. A broader typed representation still
requires the separate numeric-width migration, authoritative-handle ABI review,
fresh storage/RSS/access/sort measurements and full interop acceptance evidence.
Exact final-head CI/distribution and postmerge checks are reported on PR #278;
cancelled or superseded runs never count as passes.

## Approved shrink fix: fresh paired evidence

Fresh baseline is main `694683c0`; after contains the approved non-clearing
shrinking writers. The generated program/harness is byte-identical, with pinned
SDK and the same CPU/GC/pairing settings above. Source/runtime/binary hashes and
dirty-build provenance are in [non-clearing results](results/non-clearing/provenance.json).

| Case | after/before time | paired 95% interval | median bytes before / after | allocations before / after |
| --- | ---: | --- | ---: | ---: |
| Read-only callback | 1.007 | 0.995–1.024 | 2,622,749 / 2,622,669 | 131,095 / 131,093 |
| Write inside callback | 0.924 | 0.907–0.941 | 3,672,037 / 2,623,380 | 131,107 / 131,104 |
| First write after callback | 0.923 | 0.907–0.945 | 3,671,789 / 2,623,130 | 131,109 / 131,106 |

Writing paths retain the 1 MiB/three-allocation reduction and are faster in 12/12
and 11/12 pairs. Read-only removes 80 bytes/two allocations; its timing interval
includes parity, so the new runs establish no read-only speedup. The earlier
table remains historical evidence for its own code/host period.

## Retained references

The approved semantics deliberately change reclamation after shrinking. A worker
constructs 4,096 Bytes values with 8,192-byte payloads, touches every OS page using
ordinary Go writes, then performs actual native List operations. Before is current
main `694683c0`; after has the no-copy/non-clearing fix. Three fresh processes per
variant/case use random order, CPU 0, GOMAXPROCS=1, GOGC=100, no GOMEMLIMIT.
Forced GC plus supported `debug.FreeOSMemory` makes retained heap and post-scavenge
Linux VmRSS observable. These are diagnostic memory controls, not execution timing.

| Operation | retained heap before / after | post-scavenge RSS before / after (KiB) |
| --- | ---: | ---: |
| Splice all values to empty | 65,600 / 33,718,336 B | 7,952 / 40,784 |
| Delete all but the last value | 73,816 / 33,710,120 B | 7,992 / 40,844 |
| Remove repeatedly from the end | 65,600 / 33,718,336 B | 7,972 / 40,808 |
| Clear then overwrite all capacity with explicit empty Bytes | 65,600 / 65,600 B | 7,980 / 7,952 |
| Clear then explicitly release the Go receiver header | 64 / 64 B | 7,912 / 7,884 |

Non-clearing empty Lists retain about 32.1 MiB more payload/reference heap in this
control. Peak RSS is about 39.7–40.1 MiB on both sides because construction already
reaches that high-water mark. Reusing all slots or releasing backing references
allows reclamation. Dropping all source aliases can release the List and its
backing; a running captured range independently keeps its array alive until done.
No implicit copy, capacity trimming, weak references or zero-value policy hides
this cost. Resource close/lifetime rules remain lexical and independent of GC.
Raw samples, binary hashes and medians are in [retention.json](results/non-clearing/retention.json).

To rebuild the worker, copy `retention.go.txt` into an ignored directory within
each checkout's Go module and build it with that checkout's bundled SDK:

```sh
toolchain/go/bin/go build -mod=vendor -tags=ms_lean \
  -o .artifacts/list-retention/worker ./.artifacts/list-retention
python3 scripts/bench-lists/retention.py \
  --before /path/to/before-worker --after /path/to/after-worker \
  --output .artifacts/retention --runs 3 --cpu 0
```
