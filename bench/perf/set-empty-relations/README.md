# Empty-right Set disjointness

The baseline scans every left member for `left.is_disjoint_from(empty)`, even though membership in the empty set needs no hashing. The candidate returns true immediately when the right set is empty. All other relation paths retain their existing traversal and user-defined callback behavior. No ABI, compiler, lifetime, or public API change is involved.

## Environment and method

Measured 2026-10-31 on fresh main `3cfde58b6` versus the saved candidate patch, AMD EPYC 9V45, Linux x86-64, affinity CPU 0. Rust/Cargo 1.99.1; generated inventories report `cranelift`, `Release`. Rust uses `-C opt-level=3 -C overflow-checks=on -C force-frame-pointers=yes`. No backend settings or implementation were changed. Native runtime uses normal Cargo release defaults. Environment/source/binary hashes accompany the raw results.

`measure.py` covers 126 cases: subset, superset, disjoint; sizes 0/1/8/128/4096/65536; equal, empty-left, empty-right, disjoint, small-right, early and late decisive members. Six rotating samples balance before/after/Rust order. `focused.py` uses twelve longer samples for 50 empty/nonempty controls. Setup/build/warmup are untimed. Every producer's status, stderr, output shape, positive elapsed time and independently computed exact Boolean checksum are checked before recording it. Reports start incomplete and become complete only after every row passes; existing evidence is not overwritten.

`measure-maps.py` supplies 52 unrelated Map controls: integer/string hit-and-miss lookup and existing-key update followed by lookup, sizes 0/1/8/128/4096/65536, string prefixes of 0/16/256 bytes and 4096 bytes at medium sizes. `focused-maps.py` extends 18 medium/large controls to twelve samples; its retained dataset is from the initial `d4a94aa92` baseline before source whitespace formatting. The fresh-main 52-case matrix uses the final formatted source. Input preparation is untimed; updating owned String keys includes key cloning in both languages. Lookup returns scalar values. All outputs must equal the known integer sum, including zero for absent keys.

Rust controls use idiomatic `HashSet`/`HashMap` with their default randomized hasher. Manuscript preserves insertion order, while Rust set iteration order varies: early/late patterns describe Manuscript insertion order, so do not treat those Rust ratios as equal amounts of scan work. Both compute the same set relation. Rust inputs/results use `black_box`; both producers consume results in printed checksums. Tiny batches and zero-element loops are timing-overhead controls, not precise speedup measurements. No universal Rust parity claim is made.

Queries perform no output collection construction; no allocation reduction is claimed. Valgrind instruction profiling was unavailable through the configured package catalogue (`apt-get download valgrind`: no candidate); wall timings and callback tests are the evidence here. Other platforms and a future combined campaign main were not measured by these saved samples.

`measure-growth.py` adds 32 cases for integer/String insertion into fresh maps and integer remove/reinsert churn, with the same sizes, prefix stress, oracle and rotation protocol. String churn was not executed: `remove(keys[i])` reaches an ownership diagnostic about moving a list element, and ownership investigation/workarounds are outside this campaign lane. That path is blocked, not clean.

## Results

Fresh-main median batch milliseconds; compare only corresponding rows. Raw samples retain every trial and distribution.

| Query, left size, right pattern, repetitions | Before ms | After ms | Rust ms |
| --- | ---: | ---: | ---: |
| disjoint, 1, empty-right, 1000000 | 3.343480 | 1.134582 | 0.852538 |
| disjoint, 128, empty-right, 10000 | 2.216104 | 0.012028 | 0.008568 |
| disjoint, 65536, empty-right, 20 | 2.057357 | 0.001478 | 0.000166 |

At 128 members, the candidate avoids traversal for every query. At 65536, the candidate/Rust batches are dominated by timing/query-loop overhead; their ratios are not precise per-query speedups.

Nonempty fresh-main Set full-matrix ratios span 0.899–1.277, including microsecond batches. The 50 longer controls narrow nonempty equal/disjoint ratios to 0.882–1.017. Nine additional twelve-pair decisive-query controls (`decisive.py`, before/after only) cover the microsecond cases with a million queries per batch; their ratios span 0.978–1.007. Rust is omitted from this focused run because randomized iteration can turn a first-answer Manuscript case into a full Rust scan. The interrupted three-producer attempt remains incomplete in local campaign evidence and is excluded from results. In particular, the short unchanged `superset(1, empty-right)` control initially measured 1.078x, while its longer twelve-pair comparison measured 1.001x. The short observation was retained, not discarded. Fresh nonempty Map lookup/update ratios span 0.951–1.039; insertion/churn controls span 0.961–1.019. The earlier 18 longer Map controls span 0.978–1.006. These ranges describe these runs, not a cross-platform guarantee.

Remaining Rust gaps vary with size, hash implementation and key length. Native string lookup/update at 4096 entries with long common prefixes can remain slower than Rust. Sampling profiling reported only `main` and `[runtime]`, which cannot attribute a fix to a permitted helper; no native-hash or backend change is justified by that profile alone. Integer churn at 65536 entries is also slower than Rust in this pass; no causal patch was established. This evidence does not declare the entire lane clean.

## Reproduce

Build `ms` at the pinned baseline in an isolated checkout with `cargo xtask runtime` then `cargo build --release --locked -p ms-cli`; save that compiler. Build the candidate normally in another checkout. Do not share a stale embedded runtime archive. Use writable `XDG_CACHE_HOME` where required. The saved patch applies to the baseline.

```sh
/path/to/before-ms build bench/perf/set-empty-relations/main.ms --build-type Release -o /tmp/sets-before
/path/to/after-ms build bench/perf/set-empty-relations/main.ms --build-type Release -o /tmp/sets-after
rustc --edition=2021 -C opt-level=3 -C overflow-checks=on -C force-frame-pointers=yes bench/perf/set-empty-relations/rust/main.rs -o /tmp/sets-rust
taskset -c 0 python3 bench/perf/set-empty-relations/measure.py /tmp/sets-before /tmp/sets-after /tmp/sets-rust /tmp/new-set-samples.json
taskset -c 0 python3 bench/perf/set-empty-relations/focused.py /tmp/sets-before /tmp/sets-after /tmp/sets-rust /tmp/new-set-controls.json
taskset -c 0 python3 bench/perf/set-empty-relations/decisive.py /tmp/sets-before /tmp/sets-after /tmp/new-decisive-controls.json
```

For Map controls, build `maps-control.ms` with both compilers and `rust/maps-control.rs` with the same Rust flags, then run `measure-maps.py` and `focused-maps.py` with the three binaries and new result paths. Growth controls use `maps-growth-control.ms`, `rust/maps-growth-control.rs` and `measure-growth.py` similarly. Select an allowed CPU; do not run other compilation or benchmarks concurrently.

## Validation and limits

`empty_set_relations_do_not_hash_members` checks nine result directions and zero user hash calls for empty operands. The existing `set_relations_stop_at_first_decisive_key` protects nonempty callback short-circuiting. The 126-case native matrix checks actual source programs. Broader runtime/lifetime, backend and platform validation is outside this lane; normal required CI remains enabled.

Smaller-side Set traversal remains a separate design question because it changes callback order. Earlier SortedMap extraction and BitSet expression experiments were rejected after independent review and common-path controls; they are not part of this production change.
