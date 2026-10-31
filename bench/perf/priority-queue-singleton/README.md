# Rejected singleton PriorityQueue experiment — 2026-10-31

**Neither candidate is retained. Production code and live fixtures are unchanged.**
A singleton fast path improves one-element batches, but repeated longer controls
reproduce a small-heap regression and regressions in unchanged Queue/Deque
workloads. This report preserves the rejection rather than publishing only the win.

## Baseline and method

Baseline: `d4a94aa9283348133542078e22ccaa3b2c9dc348`, re-fetched unchanged after
the search pass. Host: Linux x86-64, AMD EPYC 9V45 96-Core Processor, five logical
CPUs exposed to the container; no CPU affinity pinning. No concurrent build or
benchmark ran during timed trials.

Rust/Cargo 1.99.1 (`58cf8f9c3`, 2026-10-13), official musl targets, and the
repository-pinned tools were installed. Manuscript CLI: `cargo xtask runtime`,
then `cargo build --release --locked -p ms-cli`. Programs use `--build-type
Release`. The artifact metadata reports `build_type: Release`, `backend:
cranelift`; LLVM tools 23.1.1 were available. Backend selection/implementation
was not investigated under this campaign's exclusions. Rust uses edition 2024,
`-C opt-level=3 -C overflow-checks=on -C codegen-units=1`.

Both programs prepare identical integer inputs outside timing, then enqueue and
drain the complete collection repeatedly. Deque pushes alternate ends before
draining from the front. Rust uses `BinaryHeap<Reverse<(value, sequence)>>` for
the stable min-priority contract and `VecDeque` for FIFO/double-ended work.
Every produced value contributes to an order-sensitive weighted checksum, checked
against an independent Python oracle; zero-size cases remain explicit controls.
Rust input/result barriers and Manuscript `keep` preserve observable results.
These are composed collection workloads, including checksum traversal, rather
than isolated native-call costs.

Six paired, rotating before/after/Rust trials cover 36 cases: empty, singleton,
8, 128, 8,192 and 100,000 elements, random/duplicate priorities, and three
collection kinds. Each version runs once to warm up before recording. Longer
controls use 16 trials and 10 million elements per batch. The A/A control runs
the identical baseline executable under both labels. Source, patch, executable,
tool and revision identities accompany the raw samples; the optional `candidate`
label means the patched Manuscript program, not a second Rust version.

## Rejected changes

`extra-branch.patch` adds `count == 1` after the empty check and performs the
same order/heap pops while skipping self-swaps and an empty sift.
`grouped-guard.patch` folds both cases into `count <= 1`, keeping one admission
condition for larger heaps. Both preserve comparator order, return values,
capacity behavior and the enqueue sequence counter for valid queue state.

The first actual-library run improved singleton batches but regressed eight-item
random heaps by 11%. The grouped revision did not fix the tradeoff: its full
run regressed those heaps by 22%, and the longer run reproduced that result in
all 16 paired samples. Both variants were restored to unapplied patches.

## Longer grouped-guard controls

Times are median **ns per complete batch**, including enqueue, dequeue and
checksum work. Ratios use the median of 16 paired after/before samples. A ratio
above 1 is slower. Ranges retain the complete paired distribution.

| Workload, size | Before ns | After ns | Rust ns | Paired ratio [min, max] | A/A paired ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| PriorityQueue, 1 | 11.894 | 4.504 | 2.321 | 0.377 [0.360, 0.449] | 1.003 |
| PriorityQueue, 8 | 112.726 | 138.464 | 67.050 | 1.224 [1.187, 1.310] | 1.000 |
| PriorityQueue, 128 | 2570.790 | 2642.089 | 2257.053 | 1.028 [1.013, 1.045] | 1.002 |
| Queue, 8192 | 42871.521 | 47280.059 | 16370.585 | 1.104 [1.067, 1.174] | 0.998 |
| Queue, 100000 | 525699.720 | 579351.900 | 195698.105 | 1.108 [1.065, 1.256] | 1.001 |
| Deque, 8192 | 44790.230 | 46279.469 | 16978.575 | 1.040 [0.997, 1.103] | 0.996 |

The singleton result remains about 1.94x Rust, even after the rejected change.
The cause of regressions in unchanged controls is unresolved. These measurements
do not justify attributing them to one instruction, placement, or allocator.
No alignment/padding tuning or backend investigation was attempted.

Raw experiment evidence: `extra-branch-samples.json`, `grouped-samples.json`,
`focused-samples.json`, and `aa-samples.json`. These 2,124 invocations (including
warmups) completed successfully; 1,872 timed samples were validated against exact
per-case checksums.
No allocation/RSS instrumentation was performed; storage/lifetime investigations
were outside the lane's authorized scope.

## Validation and reproduction

Independent review checked both guards, the stable-heap contract and fixture,
the independent FIFO/Deque oracle, integer bounds, sample completeness and
balanced ordering. `candidate-tests.ms` passed both tests in Debug and Release
against each candidate. Five existing source sorting tests and three selected
FIFO/PriorityQueue tests passed during discovery. Full native conformance and
workspace execution were not run locally under the campaign's restricted scope.
Required CI is unchanged.

Fresh-main replay: `dd48b4ddf01149617b4698e3fe7905e3095ee2f4` was fetched,
the CLI rebuilt, and the entire 36-case matrix repeated with no candidate applied
(`fresh-main-samples.json`, 756 further invocations / 648 timed samples). The
generated collection program is byte-identical to the original baseline, SHA-256
`da31c2c49540b4d4d2d6468e8eb14112bacf58e48bf084ca0d7fd33a27207a70`.
Existing gaps remain; this is no evidence of universal Rust parity. The five
reports together contain 2,880 successful invocations and 2,520 timed samples.

Use the baseline CLI and a separately built CLI with exactly one saved patch.
Build identical `main.ms` with both CLIs; retain each build artifact's metadata.
Pass the baseline revision, versions, flags and patch hashes in a metadata JSON
with the same schema as the recorded files. The runtime cache can live at a
writable `XDG_CACHE_HOME` without changing repository pins or security settings.

```sh
"$MS_BEFORE" build bench/perf/priority-queue-singleton/main.ms --build-type Release -o /tmp/pq-before
"$MS_AFTER" build bench/perf/priority-queue-singleton/main.ms --build-type Release -o /tmp/pq-after
rustc --edition 2024 -C opt-level=3 -C overflow-checks=on -C codegen-units=1 \
    bench/perf/priority-queue-singleton/main.rs -o /tmp/pq-rust
python3 bench/perf/priority-queue-singleton/measure.py \
    /tmp/pq-before /tmp/pq-rust /tmp/full.json /tmp/metadata.json 6 /tmp/pq-after
python3 bench/perf/priority-queue-singleton/focused.py \
    /tmp/pq-before /tmp/pq-rust /tmp/focused.json /tmp/metadata.json 16 /tmp/pq-after
python3 bench/perf/priority-queue-singleton/focused.py \
    /tmp/pq-before /tmp/pq-rust /tmp/aa.json /tmp/metadata.json 16 /tmp/pq-before
"$MS_AFTER" test bench/perf/priority-queue-singleton/candidate-tests.ms --build-type Debug
"$MS_AFTER" test bench/perf/priority-queue-singleton/candidate-tests.ms --build-type Release
python3 -m unittest discover -s bench/perf/priority-queue-singleton -p 'test_*.py'
```

This is not a clean bill for sequence performance. Queue/Deque/PriorityQueue
still trail the matched Rust controls. Broader discovery also covered reverse
search; a countdown variant was rejected for 6–8x short-hit regressions. Pure
sorting/concatenation timings from an earlier harness remain provisional because
fresh per-iteration work was not established, and are not used as confirmed gaps
or acceptance controls here. Untested paths and excluded mechanisms remain open.
