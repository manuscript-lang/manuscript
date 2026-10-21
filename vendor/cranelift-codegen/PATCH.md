# Local change to cranelift-codegen 0.136.0

This is the published crate with one addition to the x64 backend (`src/isa/x64/inst.isle` and `lower.isle`):
a `brif` or `select` on the flag output of `sadd_overflow`, `ssub_overflow` or `usub_overflow` branches on the
flags of the `add`/`sub` itself (`jo`, `jb`) instead of materializing the flag with `seto`/`setb` and testing it.
Upstream already does this for `uadd_overflow`, `umul_overflow` and `smul_overflow`.

Manuscript's checked `Int` arithmetic is `sadd_overflow` plus a branch to a cold fault block, so the change removes
two instructions from every checked addition and subtraction on x86-64.

Wired in through `[patch.crates-io]` in the workspace `Cargo.toml`. Drop the directory and the patch entry when
a Cranelift release contains the same rules. The crate's own license is `LICENSE`.
