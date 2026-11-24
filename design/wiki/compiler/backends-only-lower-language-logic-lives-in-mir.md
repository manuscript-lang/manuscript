[Wiki](../index.md) › [Compiler and build](index.md)

# Backends lower; the stack-depth protocol and layouts live in MIR

Decision (owner, 2026-11-16): language logic is written once in MIR and the backends only lower it. Done so far: `ms_mir::depth` expands `depth.enter` after `unwind` into `stack.low`, a branch and a heap block handed to `msrt_task_grow` with a MIR grow shim (`<fn>.grow`); `Layouts::closure` is the one closure object layout; `ms_rt_abi::IFACE_TAG_*` name the vtable tag bits.

Verified: the new instructions carry `Loc::NONE`, because a location on the grow call adds a frame to the overflow trace (`testrunawayrecursionisafault-1`). Cranelift lays out the second branch target first and the grow block is in `Func::cold`, so `lower_term` swaps the branch to keep it second; without the swap fib cost 4% more instructions. Anything that compiles MIR directly (tests, examples) must call `ms_mir::depth::lower` first.

Glue (2026-11-17): drop, clone, slot, block and closure functions are made in `ms_mir::glue` (`run_and_expand`: the glue pass and `expand_owned` repeat until nothing new is wanted, because closure bodies and expansions drop more types). Backends make only copies of bytes, plain lists, interfaces and nullable optionals, and cleanup thunks, and assert nothing else. A chain such as `Cons(head, tail)` is cloned by a loop (a recursive clone ran a 3M-node copy 60% slower). Anything that compiles hand-built MIR must call `ms_mir::glue::run_and_expand`, not `expand_owned` alone.

Verified failures: the Cranelift-only PR CI skipped the LLVM leak sweep and merged a glue leak (#4327); a pass that stopped after making only closure functions broke LLVM release builds that only `tools/close-matrix.ms` ran (`closure_escape_*`). For a glue or lowering change run `make conform` and `CONFORM_LEAKS=1 make conform-llvm`, `make poison-check` and `tools/close-matrix.ms` before merging.

Apply when: moving another backend-written protocol into MIR, or changing how recursive functions start.
