# Cranelift output survey, 2026-11-13

Revision `da3d27c9` plus these changes. Machine: shared 4 vCPU Linux VM. Programs: the ten agent-challenge reference solutions in `bench/agent/challenges/*/solutions/ms` fed their largest hidden stdin repeated to about 3 MB (min of 5 runs, seconds), built with `MS_BACKEND=cranelift` (Release) and the default Debug profile. CLIF comes from `MS_DUMP_CLIF=1`, machine code from `objdump -d`, instruction counts from `valgrind --tool=callgrind`.

## Change: conditional moves for branches that join one block

| program | Release before | Release after | LLVM Release |
|---|---:|---:|---:|
| c14-dp-suite | 1.80 | 1.06 | 0.65 |
| c13-inventory-orders | 0.303 | 0.284 | |
| every other program | within noise | | |

Debug is unchanged by design.
