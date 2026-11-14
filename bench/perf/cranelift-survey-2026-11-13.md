# Cranelift output survey, 2026-11-13

Revision `da3d27c9` plus these changes. Machine: shared 4 vCPU Linux VM. Programs: the ten agent-challenge reference solutions in `bench/agent/challenges/*/solutions/ms` fed their largest hidden stdin repeated to about 3 MB (min of 5 runs, seconds), built with `MS_BACKEND=cranelift` (Release) and the default Debug profile. CLIF comes from `MS_DUMP_CLIF=1`, machine code from `objdump -d`, instruction counts from `valgrind --tool=callgrind`.

## Change: conditional moves for branches that join one block

| program | Release before | Release after | LLVM Release |
|---|---:|---:|---:|
| c14-dp-suite | 1.80 | 1.06 | 0.65 |
| c13-inventory-orders | 0.303 | 0.284 | |
| every other program | within noise | | |

Debug is unchanged by design.

## Change: no Cranelift IR verifier in shipped builds

`enable_verifier` is on by default in Cranelift and was 18% of all instructions (35% of Cranelift's own time) when building a generated 64,000-line program (4,000 functions, 300 for the callgrind run). Builds of `ms` with debug assertions, which is what the test suites run, keep it; `MS_CLIF_VERIFY=1` turns it on anywhere.

| build of the 64k-line program | verifier on | verifier off |
|---|---:|---:|
| Debug, wall (s, 3 runs) | 3.52 to 3.74 | 3.06 to 3.20 |

## Change: a remainder and a quotient of the same operands share one divide

`i % n + i / n` took two `idiv` instructions; LLVM emits one. The lowering now divides once per pair of operands in a block and derives the other result (`x - q * y`, or `-x` for a divisor of -1). Loop of 30M iterations with a variable divisor: 0.190 s to 0.101 s (LLVM 0.100 s). Constant divisors compile to the same code as before.

## Findings not fixed, ranked by what they would buy

1. **Loop-carried values live on the stack in loops with many live values.** In `edit` (c14) the list pointers and lengths of `prev` and `cur` are reloaded from the frame several times per iteration, and `spill_loop_cold` only helps values the loop never touches. LLVM Release still runs c14 in 0.65 s against 1.06 s after the select change. The register allocator splits live ranges badly around loops; fixing it means reducing live values in lowered loops (fewer flattened list leaves kept live) or changing the allocator. Large, uncertain.
2. **Indirect calls through the GOT for every runtime call** (`mov rax, [rip+got]; call rax`). Marking runtime calls colocated gives direct calls (376 indirect calls to 97 in c36). Tried: all ten programs within noise, so not worth the macOS and Windows risk.
3. **A 32-bit divide when both operands are small**: LLVM does not do it on this CPU either (its gap here was the shared divide, fixed above), so skip unless a CPU with slow 64-bit divide is measured.
4. **No loop rotation**: each loop pays a taken `jmp` back to a test at the top. About one cheap instruction per iteration.
5. Rejected after measuring: folding boolean `not` into the comparison and turning `select a, b, false` into `and` both gave more instructions on c09 (48.23M and 48.30M against 48.15M); one allocator pass for all Debug builds saved 10% of codegen and made Debug code 40% slower on c14.
