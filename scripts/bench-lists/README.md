# Numeric List storage measurements and staged representation plan

**Current direction:** Int/Float remain 64-bit; the user cancelled the width
migration. Primitive production storage and its access/comparator seams are now
implemented in [the typed storage review](typed-storage.md). Earlier numbers and
prototypes below remain historical evidence. List traversal captures backing and
initial length, with visible writes and non-clearing retained tails.

Refs #142 and #87. This directory contains checked Manuscript workloads, a
generated-Go benchmark runner, fresh-process allocation/RSS workers, and an
isolated typed-storage experiment. The experiment is **not** a runtime ABI or
language feature. The old prototype is separate from the production implementation described above.

Run from the checkout root with its bundled SDK:

```sh
make payload
toolchain/go/bin/go run ./scripts/bench-lists -output .artifacts/list-bench -count 3
python3 scripts/bench-lists/memory.py --binary .artifacts/list-bench/lists.test \
  --output .artifacts/list-bench/memory --runs 3
make build
python3 scripts/bench-lists/native.py --cli ./ms \
  --output .artifacts/list-bench/native --runs 3
```

Set `GOCACHE`, `GOPATH`, and `XDG_CACHE_HOME` to writable directories when needed.
The Python RSS workers use Linux `wait4` (KiB `ru_maxrss`) and `/proc/cpuinfo`;
the Go benchmarks and prototype do not depend on Linux. `--cpu N` selects an
available CPU for the Python workers. Pin Go benchmarks with `taskset` if desired.
Builds and warm-ups are excluded from native timing. Allocation workers force
GC before construction and again while retaining the completed list; their
wall times include those collections, verification and process startup. They
must not be compared directly with the Release programs' wall times. Checksums,
sort order and unchanged source storage are checked separately from timing.

The runner retains emitted Go, source and its native test binary. The Release
runner retains each `.ms`, emitted Go, native executable, artifact metadata and
raw samples. The allocation worker records binary SHA-256, revision, dirty
status, CPU/affinity, Go version, GC environment, capacity, raw samples and
medians. Preserve these files with published measurements.
The recorded samples and source/binary hashes are in [results](results/).

## Measurement findings

Initial baseline: main `5b482774b68e0e5eb281492b3543d33a8f26dc52`, including
merged #218/#223/#224/#232, bundled Go 1.25.1, Linux amd64, Intel Xeon Platinum
8573C. Old issue figures are not this baseline. Wall times varied substantially
with host/compilation contention; allocation counts and retained heap are the
strongest evidence here. No wall-time speedup is promised by these experiments.
The bounded slice was rebased onto main `93fcb4fe`; repeated generated-operation
benchmarks retain the same allocation counts. The two baselines' raw runs are
retained separately rather than relabeling the earlier samples.
Final integration base is `7bd79bb0`, including #244's additional Map/Set
callback/output evidence and #214's source-call depth, record and fault handling.
Fresh before/after operation samples on that base retain the 1 MiB membership
allocation reduction; they are separate files under `results`. New source-call
wrappers materially change timing, so the earlier wall samples remain historical.

Separate fresh Release programs on unmodified `93fcb4fe` (three samples, CPU 1,
default GC) measured:

| Program | median wall seconds | median peak RSS (MiB) |
| --- | ---: | ---: |
| Append 1M Ints | 0.198 | 75.6 |
| Append 4M Ints | 0.998 | 272.6 |
| Build and stable-sort 200K Ints | 1.166 | 32.0 |

These timings include process startup/shutdown and differ from the Go benchmark
loop and allocation workers. See raw samples for variation; the earlier issue's
machine and code are different, so these numbers are not a paired speedup claim.

For 65,536 elements, fresh generated-Go baseline medians:

| Operation | ns/operation | allocated bytes | allocations |
| --- | ---: | ---: | ---: |
| Build by append (whole list) | 8,585,351 | 6,585,515 | 130,681 |
| `at(...).unwrap()` accumulation (65,536 reads) | 12,940,622 | 6,813,724 | 327,424 |
| `for` accumulation (whole list) | 2,077,666 | 524,282 | 65,535 |
| `for_each` accumulation (whole list) | 9,194,572 | 2,622,640 | 131,093 |
| Stable sort with a source comparator (whole list) | 267,718,501 | 52,647,448 | 2,225,800 |

These benchmark function calls use real lowering, checked Int arithmetic,
source wrappers/fault positions and cancellation. They exclude compilation and
process startup. The generated append loop also boxes its index local; the
generated accumulation loops also box arithmetic results. Do not attribute all
their allocations to element storage.

Fresh-process 4M-element allocation controls separate those costs:

| Construction path | allocated bytes | allocations | retained heap bytes |
| --- | ---: | ---: | ---: |
| Generated source | 402,018,832 | 7,989,553 | 131,638,752 |
| Current boxed runtime, concrete scalar locals | 370,020,832 | 3,989,806 | 99,722,752 |
| Isolated typed handle, concrete scalar locals | 160,716,088 | 46 | 32,284,104 |

The latter two use matching concrete scalar locals, checked arithmetic and
cancellation. Both grow by ordinary Go append without preallocation. Final
capacity is 4,237,824 boxed versus 4,035,584 typed; retained storage is about
24.9 versus 8.1 bytes per source element in these controls. Those are observed
whole-process heap differences, not an allocator/ABI guarantee. Peak RSS also
includes old growth arrays, GC headroom, stacks and process overhead. Initial
generated 4M-element samples peaked at roughly 302 MiB versus 108 MiB for the
typed experiment. Do not extrapolate a constant RSS cost from one list length.

Boxing at reads and callbacks can negate gains. On the same 65,536 values,
typed storage sorted through the **same generated source comparator** and
ordinary `Invoke` allocates about 74.6 MB / 5,035,879 objects, versus 52.6 MB /
2,225,800 for current boxed storage. Already boxed elements can be reused by
the latter. Typed reads producing ordinary Optional payloads also add payload
boxing. Conversely, current boxed storage traversed with concrete accumulation
locals needs only one result allocation, just like typed traversal. Storage,
scalar-local lowering, Optional elimination and callback ABI specialization
are separate optimizations and must be measured separately.
With matched concrete accumulation/index locals, boxed storage indexing uses
131,073 allocations / about 5.24 MB per 65,536 reads, while the typed experiment
through the same Optional ABI uses 196,444 / about 5.77 MB. This is an allocation
regression of about 50% despite the much smaller retained backing storage.

## Current no-copy traversal follow-on

The [Go range review](go-range-review.md) records the authorized List-only
semantic change, deterministic Go-reference cases, zero-allocation boundary and
paired normal-runtime and retained-memory evidence. Shrinking uses non-clearing
shift-and-reslice semantics; prior values remain in spare capacity until overwritten
or released, preserving valid typed consumption by a captured traversal.
Primitive storage is now typed; see the current review above. Numeric widths remain unchanged.

## Historical bounded COW change

The [narrow review](narrow-review.md) records exact correctness/concurrency/native
writer boundaries, snapshot-edge coverage, and paired normal-runtime results.

The earlier #247 List callback traversals retained a private, capacity-limited membership
header and mark the receiver's backing array shared, using the existing loop
COW mechanism. A read-only 65,536-element snapshot costs 48 bytes / one
allocation rather than a 1,048,624-byte clone / two allocations. Generated
`for_each` accumulation falls from about 2,622,640 to 1,574,064 allocated bytes,
removing exactly the 1,048,576-byte membership array. Callbacks' own boxing and
dispatch remain measurable costs.

All writes to existing elements must detach. `fill`, `copy_within`, and
`reverse` had omitted `ownItems` and corrupted active loop snapshots;
#247 made them detach as the other mutators already did. A source fixture failed on
its unmodified baseline and passed after this correction. Append could reuse
capacity because appended values lie beyond captured membership. Clones keep
independent outer storage; nested and recursive references remain shared.

The conservative `shared` flag has no snapshot-release tracking, matching the
existing loop policy. A first later in-place write can therefore copy storage
even after the callback completes. A callback that writes immediately pays the
copy that eager snapshotting previously paid; repeated writes reuse detached
storage. Long-lived saved callbacks retain the original list handle. This
bounded change does not solve boxed element storage or callback dispatch cost.

## Authoritative typed representation

The current [Go representation guide](../../documentation/contributing/go-lowering-representation.md)
defines the implementation and migration. A single `*List` owns its typed slice
header directly, retaining two constructor allocations without a separate backing
owner. Captured headers are traversal views, never mutable owners. No boxed mirror
exists. The earlier three-allocation Int prototype remains a historical control.
Default Int/Float widths are 64-bit; closed width experiments stay closed.

## Integration risks and acceptance gates

- **Go ABI:** exported `List.Items` is used by generated composites, embedded
  runtime adapters and external Go callers. Cutover is a coordinated ABI change;
  a compatibility accessor cannot support arbitrary direct writes to a mirror.
  Native/standalone embedding, implementation hashes and debugger expectations
  must move together. The typed cutover migrates consumers through the storage-aware helpers.
- **Captured backing:** audit every mutator, overlapping/self splices, callback
  reentry, early exits, cancellation and faults. Preserve shallow references.
  Synchronization remains the caller's responsibility for shared collections.
- **Equality/hash:** keep identity/cycle tracking keyed by the authoritative
  handle and preserve scoped element equality through generics/modules/views.
  Do not derive Hashable for Lists: current source declarations do not do so.
  Float behavior must retain NaN, signed-zero and hashing/equality contracts.
- **Interop:** called native tests must cover typed -> generic -> typed aliases,
  saved methods across growth, `List[Optional[T]]`, Error/Result conversion,
  nested lists/records/cycles, Lists of functions/views/resources, builders,
  source/native callbacks and synchronized access. No divergent copies at any
  boundary, including operations that return the original instance.
- **Other owners:** #147/#238 owns large literal lowering and its independent
  oracle. Immutable typed constant tables would need fresh mutable storage per
  evaluation, preserving ordered effects and source locations. The #224/#232
  Optional conversion follow-up owns argument conversion; #166 owns additive
  core APIs. This slice does not edit those surfaces.

The parent's later review holds #238's scalar-copy implementation. Its
[runtime review at `7f0a5e78`](https://github.com/manuscript-lang/manuscript/blob/7f0a5e78a3a26f180b466fb90ba7316a8bddeacf/scripts/bench-flat-literals/runtime-review.md)
confirms 1.51x slower repeated 16K construction and 1.62x slower 100K construction
under normal GC, despite roughly 12.3s -> 1.34s build time and 1.87 GiB ->
171 MiB compiler RSS. The cited CPU profiles implicate pointer-copy barrier
work; they do not establish a complete cause or a typed-storage fix. Do not
cherry-pick that held change as a dependency of this slice.

The prototype also measures copying fresh typed versus boxed backing at 16K and
100K. These are synthetic **heap-table** copy controls, not the actual source
literal/static-table implementation. Typed primitive arrays halve Int backing
bytes and omit element pointers using ordinary Go storage, making them a useful
candidate for the next literal experiment. A combined implementation must run
#147's actual source-wrapper paired construction benchmark under its GC settings,
as well as build wall time/RSS/binary size, before promotion. Preserve fresh
mutable handles/storage, alias updates and ordered effects. Faster synthetic
typed copies are insufficient evidence to accept a literal-lowering replacement.
Exploratory medians on this host were 51 microseconds / 131,128 bytes at 16K and
233 microseconds / 802,872 bytes at 100K for typed copies, versus 328 microseconds /
262,193 bytes and 1,457 microseconds / 1,605,684 bytes for boxed copies. The typed
prototype adds one small backing-handle allocation (three allocations versus
two). These three sequential smoke samples are retained in
`results/literal-copy-control.txt`; they are not paired confidence evidence.

Acceptance for the broader representation requires fresh before/after native
and allocation/RSS measurements at 1M/4M elements, indexing, iteration, callback
traversal and sorting; semantic parity through the boundaries above; and review
of the measured costs of boxed generic paths and small/empty lists. #142 and
#87 remain open. Broad representation changes must remain unmerged until the
parent reviews the evidence and migration plan.

## Verification

On integration base `7bd79bb0`, `make verify`, called native cases, native
fault/source-frame/cancellation checks, standalone emission/execution and focused
snapshot/alias/synchronized/recursive race tests pass. The complete compiler and
full runtime race suites also passed on the prior `93fcb4fe` integration base.
That prior base's four stale Decimal/reference artifacts reproduced in an
unmodified worktree; #244's combined reference regeneration cleared the drift.
No standard declarations or generated API references were changed by this slice.
