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
Existing removal/splice writers clear vacated backing cells: a captured range can
visit those cells after shrink, just as a Go range over the same `[]Value` does.
No typed zero-value policy or numeric-width migration is introduced here.

## Cleared-cell blocker

This draft remains unmerged despite green gates on `d8a83a2a`. The independent Go
oracle observes nil cells after removal; the native shrink fixture currently
ignores the yielded value. Consuming that cell as source Int instead reproduces
`interface conversion: interface {} is nil, not int64`, exit 70, with no source
frame. [Source](repro-cleared-tail.ms) and [raw reproduction](results/go-range/cleared-tail-repro.json)
are retained. Run the source with the candidate's packaged CLI:

```sh
dist/manuscript-linux-amd64/ms run scripts/bench-lists/repro-cleared-tail.ms
```

Go `[]int64` clearing would yield zero, whereas current `[]Value` clearing yields
nil. Removing clearing would retain references and change reclamation; type-aware
zeroing introduces a generic/record/function policy; a framed removed-cell fault
needs a deliberate checked boundary. Parent must resolve this contract before
merge. The fix requires consumer-level native/standalone shrink regressions and
new final-head gates. No unilateral broader representation policy is implemented.

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
