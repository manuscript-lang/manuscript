# Cancellable Synchronized blocking

Issue 148 now uses ordinary cross-task blocking and constant-time same-operation
reentry checking. The user chose this contract instead of automatic cross-task
cycle detection. The reviewed graph draft and its measurements remain preserved
at [PR 256](https://github.com/manuscript-lang/manuscript/pull/256), head
`8fa78740fa91a8a69cd02a9ee942a9559bb3e137`; that proposal was not merged.

Only lock admission changes in production runtime code. TaskGroup, Scheduler,
HTTP, work lifetime, runtime inventory and acquisition delivery are identical to
main. There is no wait graph, global dependency mutex, admission edge, per-task
wait node or removal token. PR 230's undelivered acquisition disposal is retained.

## Reproduce and interpret

Copy `pkg/runtime/synchronized_benchmark_test.go` into a prepared baseline
snapshot of `694683c04250d1d4b59f7bf19c164009d243b164`. Use the same pinned
`toolchain/go/bin/go` binary for both snapshots, writable GOCACHE/GOPATH, and
`GOFLAGS=-buildvcs=false` for scratch worktrees. Alternate baseline and candidate
order for five rounds at GOMAXPROCS=1 and 4:

```sh
GOMAXPROCS=1 toolchain/go/bin/go test ./pkg/runtime \
  -run '^$' -bench '^BenchmarkSynchronized' -benchtime=500ms -count=1
```

`samples.txt` preserves every raw sample. `results.json` records parsed samples,
the baseline SHA, measured runtime/benchmark source hashes, Go 1.25.1 and the
four-CPU Linux quota. Hardware was AMD EPYC 9V45; the host was shared, and these
are microbenchmarks rather than an application-wide speed claim.

| Benchmark / GOMAXPROCS | Baseline median ns | Blocking median ns | Baseline range | Blocking range | Both B/op | Both allocations |
| --- | ---: | ---: | --- | --- | ---: | ---: |
| Lock/close / 1 | 169.9 | 171.6 | 168.8–187.6 | 168.5–172.7 | 248 | 6 |
| Empty task lifecycle / 1 | 2997 | 3059 | 2971–3051 | 2980–3069 | 2104 | 42 |
| Independent tasks / 1 | 3017 | 3005 | 2976–3091 | 2995–3070 | 2104 | 42 |
| Lock/close / 4 | 171.2 | 169.4 | 161.2–181.7 | 159.4–178.4 | 248 | 6 |
| Empty task lifecycle / 4 | 4538 | 4490 | 4359–4695 | 4318–4593 | 2104 | 42 |
| Independent tasks / 4 | 1792 | 1734 | 1430–2055 | 1355–2185 | 2104 | 42 |

Timing ranges overlap; no reliable timing difference is established. Allocations
and retained bytes match main. The structural comparison of unchanged task and
service runtime files establishes that the proposed graph's per-task cost is
absent; timing alone is not used to prove that claim.

Ordinary wait cycles can stop cooperatively on cancellation/deadline. Cleanup
still runs shielded and joins still wait for it; cancellation is not guaranteed
to break a cleanup cycle. Bounded disposable subprocess tests explicitly release
a guard alias to let shielded cleanup finish instead of leaking blocked workers
into the test process. Same-operation reentry, delivery disposal, stale aliases,
committed updates and cancellation/release races retain regression coverage.
