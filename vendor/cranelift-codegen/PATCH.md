# Local change to cranelift-codegen 0.136.0

This is the published crate with one addition to the x64 backend (`src/isa/x64/inst.isle` and `lower.isle`):
a `brif` or `select` on the flag output of `sadd_overflow`, `ssub_overflow` or `usub_overflow` branches on the
flags of the `add`/`sub` itself (`jo`, `jb`) instead of materializing the flag with `seto`/`setb` and testing it.
Upstream already does this for `uadd_overflow`, `umul_overflow` and `smul_overflow`.

Manuscript's checked `Int` arithmetic is `sadd_overflow` plus a branch to a cold fault block, so the change removes
two instructions from every checked addition and subtraction on x86-64.

Wired in through `[patch.crates-io]` in the workspace `Cargo.toml`. Drop the directory and the patch entry when
a Cranelift release contains the same rules. The crate's own license is `LICENSE`.

A second change fixes an assertion (`value_lowered_uses == 0` in `sink_inst`) that the flag fusion
for `uadd`, `umul` and `smul` (and with this patch `sadd`, `ssub`, `usub`) can reach: the producing
instruction may be lowered twice, once folded into the branch and once on its own, and each lowering
tried to fold the same operand load into the arithmetic instruction. The fused and flags-unused rules
now take their second operand as an immediate or a register (`gpr_or_simm32`, `gpr_no_load`). Manuscript's
`random_programs_agree` test found it (26 of 1500 seeds; 6 failed before the patch because `imul.chk` already
took the path).
