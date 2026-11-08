[Wiki](../index.md) › [Testing and conformance](index.md)

# Scaling gate compares growth ratios, not wall time

Verified: about 30 bugs were passes or containers that rescan or copy per unit. `make scaling-check` (`tools/scaling-check.ms`, a gate step in CI) generates inputs at 1k, 10k and 100k and fails when `(t100k - t1k) / (t10k - t1k)` exceeds 30 (linear is about 10, quadratic about 100). The first run showed 12 to 21x for the largest compile shapes (many functions, many impls), above 10x only from cache and memory effects: callgrind shows `ms check` of many functions costs a constant ~96k instructions per function from 5k to 40k (checked 2026-11), so there is no rescan to fix. Compare instruction counts before treating a 15-20x wall ratio as algorithmic. A new pass that walks the whole function, file or list per instruction, token or element must anchor its lookups to an index-anchored side table built once, as #2979 did, never a rescan.

A single wall-clock sample is noisy: `many_impls`/`long_function emit` read 17 to 31x on the slow Intel macOS runner against a bound of 30, and a failed darwin-amd64 conformance leg was first misread as a runner-setup error (the log only echoed the script text "Wrong native Rust host"). The gate therefore re-measures a shape over the bound twice and keeps the lowest ratio; a real quadratic pass stays near 100x and still fails.

Apply when: adding a compiler pass, a formatter or LSP feature that visits a whole file, or a stdlib container operation.
Evidence: [tools/scaling-check.ms](../../tools/scaling-check.ms), [containers.ms](../../tests/scaling/containers.ms), [proposal](../../proposals/scaling-gate.md).
Verify: `make scaling-check`; add a shape to `generate` or a phase to `containers.ms` for new unbounded input.
