# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./ms sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

Reference run (Go 1.25.1, linux/amd64, four vCPUs, min of 5, microseconds):

| kernel | Go | Manuscript | Manuscript / Go |
|---|---:|---:|---:|
| sieve_5M | 64154 | 136286 | 2.12x |
| nbody_200k | 14838 | 13148 | 0.89x |
| life_128x128_50 | 62542 | 102404 | 1.64x |
| matmul_200 | 13574 | 24824 | 1.83x |
| trees_d16_x20 | 59982 | 111331 | 1.86x |
| collatz_1M | 259832 | 428103 | 1.65x |
| map_count_2M | 25499 | 42100 | 1.65x |

## Where the remaining time goes

Measured by editing the emitted Go (`ms emit`) and rebuilding; each change is independent and the numbers are relative to the same unedited build.

| Cost | Evidence | Applies to |
|---|---|---|
| Checked Int `+ - *` | removing the checks alone: collatz 1.45x, life 1.45x, sieve 1.2x | Int loops, indexes, counters |
| Cancellation poll in every loop | removing the polls alone: collatz 1.2x, life 1.1x | every loop |
| `List.Items` reloaded through the list pointer | caching the slice header in registers: matmul 1.5x, sieve 1.15x, nbody 1.1x | indexed list loops |
| Ordered Map | map_count 1.65x over `map[int]int` even with the closed Int map proof | every non-proved Map |
| Recursive sum types | each `Node` boxes two interface fields, 32 bytes against 16 for a hand pointer node, plus `Enter`/`Exit` depth counting | trees |

Literal-operand specializations of the checked helpers (`x + 1`, `3 * x`) were tried and measured no faster.
