[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Binary search moves one select per step, and a captured comparator still gets the generated sort

Verified (2026-11-18, release LLVM, `bench/perf/everyday-round5`): `List.binary_search` over 1M `Int` ran 2.9x Rust's `partition_point` because the branchy halving loop mispredicts about half its steps. A loop whose step count depends only on `size` and whose only data-dependent value is one `base = if cmp < 0: middle else: base` select runs 3x faster than Rust (31 ms against 90 for 2M searches, first-equal semantics and the logarithmic comparison budget in `e2e/stdlib/list-binary-search` kept). Two selects that both feed the loop (`base` and `size`), or an `if` on a `Bool` local, came out as branches again (147 to 465 ms), so write the comparison inline, once, in the `if`.

`ms-mir/src/opt/sortgen.rs` used to replace the runtime sort only for capture-free comparators, so `sorted(fn a, b: weights[a.key] - weights[b.key])` and `sorted_by_key` took the runtime driftsort with one indirect call per comparison (148 ms for 1M records, 3.3x the capture-free 44). The closure value is the environment pointer its code takes, so the generated sort now passes it (stored to a slot and read back as a `ptr`) instead of a dummy slot: 35 ms. `sorted_by_key` is 205 to 83 ms; the rest is its two `key` calls per comparison (computing keys once into a decorated list was no faster: 88 ms).

`msrt_list_reverse` called `swap_nonoverlapping` with a runtime size per slot pair (about 3 ns); one to four word slots now reverse as typed arrays (50 reversals of 2M `Int`, 108 to 48 ms), and `reversed` of plain slots copies back to front in one pass.

Open (2026-11-18, issue #4521): LLVM 23's early-exit vectorizer turns a pure arithmetic "find the next match" loop (a custom `Iterator` adapter over a counter, `Evens.next` filtering `Counter.next`) into a vector loop whose setup and exit cost about 50 instructions per found item: 250 ms against 39 ms with `-enable-early-exit-vectorization=false` and 48 ms for Rust's equivalent `Box<dyn Iterator>` chain. Turning it off for every build costs `contains` over a list 1.26x and `contains` over strings 1.5x, and leaves the 23-program suite unchanged, so it was not changed. A scan that loads from a list is vectorized only when the loads are provably dereferenceable, which keeps this to loops with no memory access. Revisit if a real workload shows an iterator-adapter loop; a per-loop `llvm.loop.vectorize.enable` hint would be the targeted fix.

Apply when: writing a stdlib search or sort loop, or a sort comparator that captures.
Evidence: `crates/ms-mir/src/opt/sortgen.rs` (`comparator_env`), `stdlib/collections/collections.ms` (`binary_search`), fixture `e2e/accept/sort-and-search-large-capturing`.
Verify: `MS=./target/release/ms sh bench/perf/everyday-round5/run.sh 5` rows `m_binary_search`, `r_sort_field`.
