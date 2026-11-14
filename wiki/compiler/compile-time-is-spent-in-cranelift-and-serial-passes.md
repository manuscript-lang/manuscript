[Wiki](../index.md) › [Compiler and build](index.md)

# Compile time is spent in Cranelift, LLVM tools and serial passes

Verified: 2026-11-13, 4 cores, 662 `phase=test` conformance fixtures built 40 per binary with `ms test --list` and `MS_BACKEND=cranelift`: 35.0 s before, 27.5 s after. Profile (callgrind) of one batch: Cranelift's IR verifier was 20% of all instructions, regalloc2 22%, MIR passes 25% on one core, checking 10%.

- Cranelift's verifier is off in release builds of `ms` (`enable_verifier`); debug builds and `MS_LLVM_VERIFY` keep it. It only checks this crate's own output.
- Per-function MIR passes (`simplify`, `copyelim`, `range`, `ifconv`) compute on all cores through `opt::par_funcs` and apply results afterwards. A pass run this way may read the whole module but writes only its own function, so results do not depend on thread count. A pass that reads another function's body while editing belongs outside it.
- `ms test` defaults to Release, which uses LLVM: one 40-file batch takes 26 s against 3.3 s with Cranelift and 1.9 s with `--build-type Debug`. A small program is one LLVM unit (`UNIT_BYTES`), so its `opt` and `llc` run serially: 3.3 s for `tools/close-matrix.ms`, 1.6 s with `MS_LLVM_UNITS=4`.
- Next costs, by measurement: the same standard-library code is compiled again by every binary (a content-keyed compiled-library cache was proposed on 2026-11-12), and each start re-checks the library.

Apply when: changing build profiles, `ms-clif` settings, or MIR pass structure.
Verify: `MS_TIMINGS=1 ms test <files> --list` prints phase times.
