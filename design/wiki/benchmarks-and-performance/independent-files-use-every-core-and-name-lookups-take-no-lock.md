[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Independent files use every core, and a known name is looked up without the lock

Verified (2026-11-18): `ms fmt` over 8 files took 3.28 s on one core and stopped scaling at two cores because each name the parser interns took the interner's mutex, hit or miss. A known name is now found by probing the table with atomic loads; only a new name locks, re-probes and inserts, and a table that growth replaced stays alive until the interner drops so a late reader never dangles. With that, files format in parallel (0.89 s on four cores). Any future per-file parallel work (loader parse waves, `lint`) can rely on lock-free lookups.

Verified: `ms fmt`, `ms map --format html` and LSP completion each repeated work another step had done (a second compile, a re-parse of every sibling per keystroke, parses of text just parsed). Profile a tool with callgrind and read the inclusive tree before tuning inner loops: the call counts of `parse` and `compile_file` showed all three.

Apply when: adding a tool pass that parses or compiles, or a loop over workspace files.
Evidence: [measurements](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/tool-speed/README.md), interner, parallel format.
Verify: `taskset -c 0,1,2,3 ms fmt --check <dir of 8 large files>` is about 3x faster than `taskset -c 0`.
