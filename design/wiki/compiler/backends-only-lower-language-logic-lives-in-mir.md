[Wiki](../index.md) › [Compiler and build](index.md)

# Backends lower; the stack-depth protocol and layouts live in MIR

Decision (owner, 2026-11-16): language logic is written once in MIR and the backends only lower it. Done so far: `compiler/mir/mir_depth.c` expands `depth.enter` after `unwind` into `stack.low`, a branch and a heap block handed to `msrt_task_grow` with a MIR grow shim (`<fn>.grow`); `mir_layout.c` holds the one closure object layout; `src/abi` names the vtable tag bits.

Verified: the new instructions carry `Loc::NONE`, because a location on the grow call adds a frame to the overflow trace (`testrunawayrecursionisafault-1`). Keep the grow block the cold side of its branch (`emit_term.c`). Anything that compiles hand-built MIR must run the depth pass first.

Glue (2026-11-17): drop, clone, slot, block and closure functions are made by `compiler/mir/mir_glue*.c` (the glue pass and `mir_expand.c` repeat until nothing new is wanted, because closure bodies and expansions drop more types). Backends make only copies of bytes, plain lists, interfaces and nullable optionals, and cleanup thunks, and assert nothing else. A chain such as `Cons(head, tail)` is cloned by a loop (a recursive clone ran a 3M-node copy 60% slower). Anything that compiles hand-built MIR must run the whole glue-and-expand loop, not the expansion alone.

Verified failure: a pass that stopped after making only closure functions broke release builds that only `tools/close-matrix.ms` ran (`closure_escape_*`). For a glue or lowering change run `make conform`, `make poison-check`, `make leak-check` and `make close-matrix` before merging.

Apply when: moving another backend-written protocol into MIR, or changing how recursive functions start.
