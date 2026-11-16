[Wiki](../index.md) › [Compiler and build](index.md)

# Backends lower; the stack-depth protocol and layouts live in MIR

Decision (owner, 2026-11-16): language logic is written once in MIR and the backends only lower it. Done so far: `ms_mir::depth` expands `depth.enter` after `unwind` into `stack.low`, a branch and a heap block handed to `msrt_task_grow` with a MIR grow shim (`<fn>.grow`); `Layouts::closure` is the one closure object layout; `ms_rt_abi::IFACE_TAG_*` name the vtable tag bits.

Verified: the new instructions carry `Loc::NONE`, because a location on the grow call adds a frame to the overflow trace (`testrunawayrecursionisafault-1`). Cranelift lays out the second branch target first and the grow block is in `Func::cold`, so `lower_term` swaps the branch to keep it second; without the swap fib cost 4% more instructions. Anything that compiles MIR directly (tests, examples) must call `ms_mir::depth::lower` first.

Apply when: moving another backend-written protocol into MIR, or changing how recursive functions start.
