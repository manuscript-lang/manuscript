Run from the repository root with its prepared bundled Go and writable Go
caches. The generator retains actual Manuscript, generated Go and a native
evaluation benchmark. `measure.py` is Linux-only (Python `wait4`): it records
compile/link wall time, child-tree maximum RSS, stripped binary bytes and
evaluation time/allocations. Each build edits a source comment to invalidate
the application cache. Warm dependency caches first. Checking/generation are
excluded from build measurements; startup/compilation are excluded from the
evaluation benchmark.

```sh
toolchain/go/bin/go run ./scripts/bench-flat-literals
python scripts/bench-flat-literals/measure.py --runtime .artifacts/flat-literals/current
toolchain/go/bin/go run ./scripts/bench-flat-literals -effectful -sizes=4000,16000 -output .artifacts/flat-literals/effectful
python scripts/bench-flat-literals/measure.py --runtime .artifacts/flat-literals/effectful
```

For a before/after comparison, prepare an independent checkout of the base
commit, then run this generator file there using its bundled SDK:
`toolchain/go/bin/go run /absolute/path/to/scripts/bench-flat-literals/main.go
-output /absolute/output/baseline`. Compiler imports resolve to that checkout.
Pass both output directories to `measure.py`; it reverses their order on
alternate repetitions. Record SHAs, SDK version, CPU, cache state and concurrency.

`compare.py <baseline-output>` retains controlled scalar candidates: the old
composite, private scalar data copied to fresh storage, typed data converted and
boxed each evaluation, and copies in 64/256/1024-element closures. Its
`--effectful` mode isolates Go function size with a handwritten side-effecting
scalar call and ordered assignment closures. `main.go -effectful` separately
retains actual source-call preparation, wrappers and source frames.

Pre-implementation measurements used main a6dcb33a, Go 1.25.1, Linux amd64
AMD EPYC 9V74, GOMAXPROCS=2, warm dependencies and forced application edits.
The initial candidate samples overlapped verification work; paired medians
are stronger timing evidence. These precede #218's cleanup allocation removal.

| Scalar candidate, 100,000 elements | Build | Peak RSS | Binary bytes |
| --- | ---: | ---: | ---: |
| Old composite, three-sample median | 13.1 s | 1,860,012 KiB | 9,347,256 |
| Private data copied to fresh storage, median | 1.21 s | 174,940 KiB | 7,631,032 |
| Typed conversion, initial sample | 1.11 s | 104,668 KiB | 6,029,496 |
| 64-element copies, initial sample | 11.1 s | 1,382,992 KiB | 8,843,448 |
| 256-element copies, initial sample | 9.02 s | 1,357,380 KiB | 8,466,616 |
| 1024-element copies, initial sample | 5.41 s | 845,192 KiB | 8,372,408 |

Typed conversion adds 99,744 allocations at 100,000 elements (99,747 versus 3,
including the unchanged source wrapper), so its smaller binary does not justify
it. At 16,000 elements, old/copy timing ranges overlap; both allocate 262,216 B
and 3 objects per evaluation. No runtime speedup is claimed.

| Controlled effectful candidate, 16,000 calls | Build | Peak RSS | Binary bytes |
| --- | ---: | ---: | ---: |
| One composite | 41.2 s | 6,281,848 KiB | 38,592,696 |
| 64 assignments per closure | 4.41 s | 413,072 KiB | 6,713,528 |
| 256 assignments per closure | 3.51 s | 410,000 KiB | 6,672,568 |
| 1024 assignments per closure | 4.82 s | 646,384 KiB | 6,668,472 |

All retain 16,003 evaluation allocations. The simple Go call initially favored
256, but real source-call preparation makes each element larger. Actual
16,000-element source-call measurements on base 2a9d3144 rejected the old
composite when its compiler was killed at 12,908,788 KiB RSS. The 64-assignment
candidate completed in 22.3 s / 2,218,032 KiB / 11,772,088 bytes; 256 took
53.3 s / 4,185,028 KiB / 11,710,648 bytes (repeat: 58.1 s / 4,207,912 KiB).
1024 timed out at 90 s. Thus production uses 64, accepting a small code-size
increase for less native compiler work. Timeout RSS is unavailable because
terminating the command can prevent it from reaping descendants.

The final scalar copy versus independent base 2a9d3144 retained the same two
evaluation allocations after #218: 100,000 elements compiled in median
12.3 s / 1,962,332 KiB before and 1.34 s / 175,400 KiB after; stripped sizes
were 9,339,064 versus 7,622,840 bytes. Five alternating runtime pairs at 16,000
elements ranged 61.8–94.3 µs before and 74.2–138.7 µs after (medians 89.8 and
110.5 µs); both allocate 262,192 B in two objects. Timing ranges overlap, but
the copied table may add construction/GC cost. The build-time/memory reduction
is the goal, and this is an explicit runtime tradeoff, not a speedup claim.

Arbitrary nested expressions can still have substantial compile cost. Large
flat Map literals and nested checker complexity remain outside this List change.
No mutable source object enters a data table.
