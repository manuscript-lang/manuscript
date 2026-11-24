[Wiki](../index.md) › [Testing and conformance](index.md)

# Scaling gate compares growth ratios, not wall time

Verified: about 30 bugs were passes or containers that rescan or copy per unit. `make scaling-check` (`tools/scaling-check.ms`, a gate step in CI) generates inputs at 1k, 10k and 100k and fails when `(t100k - t1k) / (t10k - t1k)` exceeds 30 (linear is about 10, quadratic about 100). The first run showed 12 to 21x for the largest compile shapes (many functions, many impls), above 10x only from cache and memory effects: callgrind shows `ms check` of many functions costs a constant ~96k instructions per function from 5k to 40k (checked 2026-11), so there is no rescan to fix. Compare instruction counts before treating a 15-20x wall ratio as algorithmic. A new pass that walks the whole function, file or list per instruction, token or element must anchor its lookups to an index-anchored side table built once, as #2979 did, never a rescan.

A single wall-clock sample is noisy: `many_impls`/`long_function emit` read 17 to 31x on the slow Intel macOS runner against a bound of 30, and a failed darwin-amd64 conformance leg was first misread as a runner-setup error (the log only echoed the script text "Wrong native Rust host"). The gate therefore re-measures a shape over the bound twice and keeps the lowest ratio; a real quadratic pass stays near 100x and still fails.

Apply when: adding a compiler pass, a formatter or LSP feature that visits a whole file, or a stdlib container operation.
Shapes with their own sizes (2026-11-15): `release_loopfree` builds a long loop-free `main` with LLVM at 800, 1600 and 6400 statements (above the size where such a function skips optimization, so one regime; the bound follows the sizes) and caught `elaborate` keeping a `Moved` entry per scope-owned temporary, which made `ms emit` of 3200 statements take 9.4 s (now 0.25 s). `test_owners` and `test_branches` build one test of 400 owners held across calls and branches and only have to pass: before #3979 the quadratic frame overflowed the test's 512 KiB task stack. The smallest input runs twice and the faster counts, because the first LLVM build pays for starting the tools.

A ratio near the bound on one platform is a real superlinear cost, not noise: `release_loopfree` read 20.1x on Windows (bound 19.1) because the MIR verifier's `dropped_in` was a `BTreeSet` cloned and extended per block edge, so 6400 statements spent 9 of 13 s verifying (callgrind: `verify_module_with` grew 4.2x for 2x the input). Per-block state in a pass is an `OwnerSet` (persistent, `union_with` shares subtrees), never a `BTreeSet`; the shape now reads 7.5x.

Evidence: [tools/scaling-check.ms](../../tools/scaling-check.ms), [containers.ms](../../tests/checks/scaling/containers.ms), [proposal](../../proposals/scaling-gate.md).
Verify: `make scaling-check`; add a shape to `generate` or a phase to `containers.ms` for new unbounded input.
