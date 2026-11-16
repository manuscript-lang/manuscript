# Stack-depth check in MIR

## Problem

`depth.enter`, the stack check of a recursive function, was one MIR op that each backend expanded by hand. Cranelift wrote the compare, the heap block of entry parameters, the call to `msrt_task_grow`, the result reload and a grow shim (`lower.rs` `depth_enter`, glue `GrowShim`). The LLVM emitter wrote the same again in four variants (`depth.rs` `enter`, `shim`, `leaf_shim`, `ret_abi`, plus `Place.grow_shim`, `Cx.entry_abi`, `Cx.ret_abi`, a `Glue` kind and its dispatch). The protocol (block layout, who frees it, where results go) existed twice, and a change needed both emitters and the runtime in step.

## Change

- New op `stack.low`: true when the stack pointer is below the running segment's limit. Both backends lower it to the one load beside the stack region's end.
- New pass `ms_mir::depth`, run last (after `unwind`, which looks for `depth.enter`). It replaces the first instruction of the entry block with `stack.low` and a branch to an out-of-line block that allocates the block, stores the parameters, calls `msrt_task_grow(shim, block)`, takes the result, frees the block and returns it. The shim is a MIR function `<fn>.grow(block)` that loads the parameters, calls the function and stores the result.
- The grow block is in `Func::cold`, so the backends place it out of line like a fault block.
- The new instructions carry no source location, so the overflow trace is unchanged.

## Evidence

- Code: about 300 backend lines deleted (`depth_enter`, `GrowShim` glue, LLVM `enter`/`shim`/`leaf_shim` and their plumbing) for about 260 lines of one MIR pass: roughly line-neutral. The gain is one copy of the protocol instead of two, so a layout or ownership change touches one place.
- Speed (callgrind, `fib(32)`): Cranelift 122,622,758 before, 122,622,751 after; LLVM 98,366,745 both. Deep and mutual recursion, aggregate parameters and results all run on both backends.
- Compile time on the generated 1,000-file project: check 1.33 s vs 1.29 s, Debug build 4.7 s and 5.3 s vs 5.4 s and 5.0 s (two runs each, noise), Cranelift release 5.3 s and 5.0 s vs 5.5 s and 5.0 s. Debug binaries are 1.6% larger (debug info for the shim functions); release Cranelift binaries are 16 bytes larger.

## Alternatives considered

- Do nothing: keeps two copies of the protocol.
- Only add `stack.low` and keep the protocol in the backends: removes the compare but not the block layout or the shims, which is most of the duplication.
- A `br.cold` hint in MIR: more general, but needs text format and persistence changes; the role already carries the one case that needs it.

## Risks

- Anything that compiles MIR without `ms_mir::depth::lower` hits an `unreachable!` in the backends (tests and examples now call it).
- A first attempt put the grow branch first and cost Cranelift 4% on fib (an extra register move per call); the branch swap above fixed it.

## Review

An independent reviewer found no wrong-code bug; its findings (the extern is `leaf: false` and always pushed fresh, more tests, stale comments) are applied. Perf evidence is callgrind on `fib(32)` per backend, not a `bench/perf` suite run.
