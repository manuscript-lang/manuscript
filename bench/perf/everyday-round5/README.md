# Everyday code round 5

Collections, iterator chains, closures, generics, interface calls, enums, records, results and graph code against Rust (`rustc -O -C overflow-checks=on`), standard library only, checksums compared. `probe.ms`/`probe.rs` are 28 small cases; `probe2` is 11 larger programs (expression trees, memo, particles, grid stencil, BFS, Dijkstra, records in maps, result pipelines), `probe3` 10 more (VM and state-machine `match`, string `match`, matmul, sieve, `SortedMap`, bound generics, record clones, optionals, statistics) and `probe4` 12 collection idioms (top-k by count, insert and remove in the middle, `concat` in a loop, `group_by`, `distinct`, set union, `flatten`, `reversed`).

```sh
MS=./target/release/ms sh bench/perf/everyday-round5/run.sh 5 [probe|probe2|probe3|probe4]
```

## 2026-11-18: Linux x86_64

Release LLVM `ms`, shared 4 vCPU VM, min of 3, microseconds. Base `121cf809`.

| case | ms before | ms after | rust | ms / rust after |
| --- | ---: | ---: | ---: | ---: |
| m_binary_search (2M searches over 1M) | 271,391 | 31,493 | 90,222 | 0.35 |
| r_sort_field (`sorted_by_key`, 1M records) | 196,210 | 68,711 | 70,716 | 0.97 |
| c_chunks_windows | 15,634 | 16,381 | 9,173 | 1.8 |

Everything else in `probe` is 0.24x to 1.17x Rust, apart from `g_max` (1.7x: LLVM vectorizes the generic max with emulated 64-bit compares on baseline SSE2; scalar would match) and `c_flat_map` (1.4x, the Rust twin appends in place without a list per element).
`probe2`: `x_dijkstra` 2.2x (`PriorityQueue`, see the wiki page on heap gaps), `x_find_first` 1.8x (4 ms), `x_compose` 1.4x (closures returning closures; each indirect call about 1 ns, the code is already a tail call), the rest 0.63x to 1.18x.

`sorted` by a capturing comparator, 1M records, 1000 keys: 148 to 35 ms (capture-free 44 ms).
`windows(3)` over 500k: 441M to 384M instructions with the outer list sized once.

`probe3` and `probe4` (min of 3): every case is 0.06x to 1.31x Rust except `z_reverse_extend` (below). Slowest: `y_match_string` 1.31 (10M `match` on a string, 1.9 ns each), `z_flatten_nested` 1.21, `y_generic_bound` 1.09, `y_sorted_map` 1.06, `y_vm` 1.04. The `HashMap<String, _>` idioms (`counts`, `distinct`, `group_by`, `to_set`, `keys().sorted()`) run 3 to 5x faster than Rust's SipHash maps.

`reverse` and `reversed` of lists with one to four word slots now move whole words instead of calling a swap per slot: 50 in-place reversals of 2M `Int`, 108 to 48 ms (same machine, alternating builds). `z_reverse_extend` first read 2.96x Rust; run alone with Rust's `rev().collect()` the same loop is 62 ms against 145 ms, so the probe's Rust twin was not doing the same work and the gap is not real.

`probe5`: custom `Iterator` types in `for`. A `Counter` iterator costs the same as a `while` loop (50 ms for 50M steps). A three-layer adapter chain over `Iterator[Int]` fields is inlined by LLVM, but the early-exit vectorizer then vectorizes the arithmetic "next even" loop: 250 ms against 39 ms with that pass off and 48 ms for Rust's `Box<dyn Iterator>` chain. Disabling the pass globally helps this loop and costs `contains` over lists 1.26x (and strings 1.5x), and the 23-program suite is neutral (A/B min of 5), so it was left on; see the wiki page.

Against Rust's fused iterators (not the materialized twin in `probe.rs`): `xs.filter(keep).map(scale).sum()` with named functions is 115 ms against 83 ms (1.4x), and `a.zip(b).map(fn p: p.first * p.second).sum()` is 36 ms against 10 ms (3.5x), because `fuse.rs` only fuses lambdas whose body reads (no calls) and does not take `zip` as a source. Extending it to calls needs a proof that the callee has no effect, which the lowering does not have; not done. `probe6` (recursive enums, interface values built per iteration, small `map`s, closures that capture): 0.45x to 1.04x Rust.
