# A branch to a cold block carries a branch weight

MIR marks out-of-line blocks `cold` (the unwind exit after a call, the fault and grow blocks `mir_expand` makes). Only Cranelift read the flag; LLVM laid the blocks out as hot, so the cleanup code sat inside loops and the register allocator treated it as likely.

`emit_terminator` now adds `!prof` branch weights (1:64) to a conditional branch with exactly one cold target. A branch with two cold or two hot targets keeps no weight.

Measured, same machine, wall min of 21 pinned to one CPU (median of 3): `interp` 267.8 to 254.6 ms (-4.9%), `hashing` 182.0 to 179.1 ms (-1.6%, run to run -1% to -4%), `dispatch` 371.1 to 363.3 ms (-2%), `exprparse` 885 to 876 ms (-1%); `lz`, `objgraph`, `treegrep`, `wordfreq`, `report` equal within noise. Callgrind instructions move the other way in one program: `interp` +6.7% (register moves in `run`, no extra branches), while `hashing` -4.1%, `objgraph` -2.4%, `dispatch` -1.8%, `exprparse` -1.2%. For `interp`, fewer taken branches beat the extra moves, so wall time is the measure here, not the instruction count.

Weight 2000:1 gave the same pattern, so the ratio is not tuned. Cranelift is unchanged.
