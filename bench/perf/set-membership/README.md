# Integer Set membership layout

## 2026-11-12: fixed layout after existing integer-key dispatch

Baseline `0cea347a5ef0d3769455ef7b96a9c6eb0bd4f976`; candidate changes only
`ms-rt::map::find_slot`'s layout computation for an already-dispatched word-key
Set. Hash/equality calls, creator descriptor selection, lookup order, and all
other layouts remain unchanged. The relevant workload in the repository's
latest general baseline is Set membership (`../baseline-2026-10-28.md`); its
historical timing is not a same-machine before/after control.

AMD EPYC 9V74, Linux 6.18.57 x86_64, shared host, CPU0 affinity and four-CPU cgroup
quota. Rust 1.99.1; Manuscript 0.1.0, pinned LLVM 23.1.1, production Release O3.
Both binaries were built from this baseline, with only the described runtime
change between them. Runtime/CLI compilation was setup and was not benchmarked.

The native `contains_key` integer branch previously loaded descriptor size and
alignment and selected a general slot layout. The candidate selects key offset
8 and stride 16 directly when there is no value descriptor. Focused native
inspection verified these loads/branches disappear; the integer hash/probe is
unchanged. This establishes removed work, not an exact attribution of every
fraction of a nanosecond: empty-set timings also moved although that path skips
layout calculation.

### Measurements

`main.ms` takes mode, size, repetitions and shape. `set` and `mapped` time
membership; shape0 hits, shape1 misses. Input/query parameters are runtime argv;
queries traverse the working set with `(iteration * 104729) % size`. Setup is
outside the monotonic operation timer, and a printed checksum consumes results.
The generic control uses prebuilt strings, so string formatting is outside its
timer. Its input domain is size 1–65,536, repetitions 0–100,000,000 and shape 0
or 1; zero/negative sizes and other arguments are outside this harness contract. All timed comparisons check equal checksums.

After four warmup pairs, 25 alternating pairs were retained for confirmations.
Batches target 60ms, capped at 10 million repetitions. Ratios are medians of paired
candidate/base times; p10–p90 describes observed variation, not a confidence
interval. Absolute times are separately computed medians, ns per membership.

| Case | Base ns | Candidate ns | Candidate/base | p10–p90 |
|---|---:|---:|---:|---:|
| Set hit, 1 | 7.031 | 6.528 | 0.925 | 0.897–1.008 |
| Set hit, 1,024 | 7.269 | 6.792 | 0.942 | 0.893–0.978 |
| Set miss, 1,024 | 6.942 | 6.457 | 0.925 | 0.889–0.964 |
| Set hit, 65,536 | 16.987 | 16.285 | 0.956 | 0.923–1.015 |
| Baseline Set A/A, 1,024 | 7.236 | 7.365 | 1.009 | 0.958–1.073 |
| Candidate Set A/A, 1,024 | 6.668 | 6.657 | 0.992 | 0.940–1.025 |
| Int/Int Map control, 1,024 | 3.981 | 3.995 | 0.986 | 0.952–1.085 |

Initial 15-pair controls also covered empty/1/64/1,024/65,536 Sets, both hit/miss,
and Int/Int Maps at64/1,024/65,536. No slowdown was established. Empty gains
(6–8%) are explicitly not evidence of saved descriptor work.

Generic fallback controls retained 15 pairs after four warmups:

| Type / size | Hit candidate/base | Miss candidate/base |
|---|---:|---:|
| String Set / 1 | 0.989 | 1.012 |
| String Set / 64 | 0.993 | 1.020 |
| String Set / 1,024 | 0.988 | 1.013 |
| String Set / 65,536 | 1.009 | 0.986 |
| Int/String Map / 1 | 0.990 | 1.017 |
| Int/String Map / 64 | 0.980 | 0.994 |
| Int/String Map / 1,024 | 1.000 | 0.988 |
| Int/String Map / 65,536 | 1.007 | 0.990 |

Shared-helper controls (`shared.ms`, positive sizes, modes `convert`/`union`)
retained 15 pairs. List-to-Set conversion candidate/base was 0.947 at 16 elements
and 0.951 at 1,024; overlapping union was 0.977 and 0.969. No regression was
established; these noisy secondary controls are not additional speedup claims.

The retained optimized-C comparison uses GCC 14.2, `-O3 -march=x86-64-v3
-mtune=generic`, a local Set implementation with identical integer hash, linear
probing, index tags and 16-byte slots. At 1,024 hit entries: C 3.992ns,
candidate 6.725ns, paired candidate/C 1.709 (p10–p90 1.616–1.821). This is a partial
improvement; it neither closes the gap nor demonstrates whole-language parity.
No new runtime entry point, compiler change or API is introduced.

### Reproduce

Use the same benchmark sources with separately built baseline/candidate CLIs.
Both builds require `cargo xtask runtime` before `cargo build --release --locked
-p ms-cli`. Build setup is outside timing. `BASE_MS` and `CANDIDATE_MS` identify
those CLI executables; do not build both programs with the same embedded runtime.

```sh
"$BASE_MS" build bench/perf/set-membership/main.ms --build-type Release -o /tmp/set-base
"$CANDIDATE_MS" build bench/perf/set-membership/main.ms --build-type Release -o /tmp/set-candidate
# Repeat alternating pairs; discard the first four pairs and summarize paired ratios.
for run in $(seq 1 29); do
    if [ $((run % 2)) -eq 1 ]; then
        taskset -c 0 /tmp/set-base set 1024 10000000 0
        taskset -c 0 /tmp/set-candidate set 1024 10000000 0
    else
        taskset -c 0 /tmp/set-candidate set 1024 10000000 0
        taskset -c 0 /tmp/set-base set 1024 10000000 0
    fi
done
```

Repeat with shape1, sizes1/64/65,536 and `mapped`; A/A uses the same executable
on each side. Build `generic.ms` analogously and run modes `strings`/`wide` with
the same sizes and hit/miss shapes. For large inputs reduce repetitions to keep
batches around 60ms. All results are warm operation costs, not end-to-end timings.
`samples.csv` exports every confirmation/generic-control pair including warmups;
side 0 is baseline and side 1 candidate, except the named A/A and C controls.
`identities.json` records executable SHA256 identities. The complete local evidence is `/workspace/scratch/set-layout` (sources,
`compare.py`, `confirm.py`, `generic-compare.py`, raw samples, identities,
statistical summaries, focused runtime disassembly and test logs). Its C control
and preceding comparison matrix are `/workspace/scratch/collections-c`.

### Correctness

`int_set_membership_keeps_collisions_holes_and_order` constructs 96 keys sharing
one final index bucket and adds signed extrema; it verifies empty/present/missing
queries, insertion order, every intermediate removal, tombstones, compaction,
clear/reinsert and allocation balance. Existing runtime tests cover custom
hash/equality callbacks, creator identity, String keys and wide Map values.
The Map/Set/sort callback and removal-to-empty fixtures also pass through both
LLVM Release and Cranelift Debug. No public semantics or ABI changes.

Local validation: 22 focused runtime tests and five compiled fixture tests per
backend passed; workspace Clippy, formatting and repository checks passed. The
broader `cargo test --workspace` attempt stopped in a debug-artifact test because
`llvm-dwarfdump` is absent. `cargo-nextest` is also absent. Exact-head CI remains
required; local results do not substitute for it.
