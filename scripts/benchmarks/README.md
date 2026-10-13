# Native runtime benchmark workloads

Build CLIs at each revision, then run (from this directory):

```sh
MANUSCRIPT_GO=/path/to/go python3 benchmark.py \
  --before /path/to/ms-before --after /path/to/ms-after \
  --output /tmp/manuscript-benchmark --runs 3
```

Set `XDG_CACHE_HOME`, `GOCACHE`, and `GOPATH` to writable paths when needed.
Run on an otherwise idle host. On Linux, `--cpu N` pins measured executions to
one available CPU; leave it unset to measure the default Go scheduling behavior.
The harness builds Release native executables and emitted standalone Go first,
then warms each executable and alternates measured before/after execution order.
Build times and warm-ups are excluded. All programs verify deterministic results
and return zero; a failed checksum aborts the run. Wall time includes native
process startup and shutdown. `results.json` includes raw samples and medians.

- `numeric.ms`: 5 million iterations of the issue #87 comment's remainder,
  comparison, conditional increment loop; checksum 2,600,000.
- `calls.ms`: 5 million calls to a two-argument source `add`, summing the index;
  checksum 12,499,997,500,000.
- `list.ms`: 5 million `List.at(i % 8).unwrap()` reads; checksum 22,500,000.
- `life.ms`: 128 by 128 toroidal Game of Life, 50 generations, using Optional
  reads and two mutable lists. The deterministic initial board has a live cell
  when `(i * 17 + (i / 128) * 13) % 7 < 3`. Final population is 3,914,
  independently checked using a Python integer/list reference implementation.

These isolate related costs but are not the original reporter's full application.
Keep Optional bounds behavior, checked Int arithmetic, and cancellation semantics
when comparing optimizations. Host contention and GC can materially affect results;
record toolchain, CPU, source revisions, and all samples with any published claim.
