[Wiki](../index.md) › [Compiler and build](index.md)

# Compile time is spent in LLVM and serial MIR passes

Verified: the C compiler has one backend. `compiler/emit` writes LLVM IR text and the loaded LLVM library makes the object file; the Cranelift backend and its numbers (verifier, regalloc2) are gone with the Rust implementation (`660429d4`).

- A program is written as one or more LLVM modules (units): `MS_UNITS` forces the count, otherwise one per core, but a module below `UNIT_BYTES` of function text is not worth a thread (`unit_limits` in `src/cli/pipeline.c`). A small program is therefore one unit and its LLVM work is serial.
- MIR passes in `compiler/opt` run on one thread. Moving a per-function pass onto several cores is only safe if it reads the whole module but writes just its own function, so the result does not depend on thread count.
- The same standard-library code is compiled again by every binary, and each start re-checks the library (`compiler/check/std_cache.c` and `lazy_std.c` limit the checking).

Apply when: changing build profiles, unit splitting, or MIR pass structure.
Verify: time `ms build` on a small and a large program with `MS_UNITS=1` and the default; measure with many runs, not one.
