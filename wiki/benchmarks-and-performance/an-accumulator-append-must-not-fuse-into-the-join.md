[Wiki](../index.md) › [Benchmarks and performance](index.md)

# An accumulator append must not fuse into the join

Verified (2026-11-14, #3879): `s += "item-{i},"` in a loop took 14 s for 200k appends in Release builds (0.1 s in Debug and `ms run`). `strfuse` fused `s + ("item-" + i + ",")` into one `string_fmtN` with `s` as its first piece, which copies the whole prefix each iteration and hides the shape `append_in_place` rewrites to an in-place `string_append`. A concat whose first operand is a loop-carried owned `s` that dies right after is left to `append_in_place` (`accumulator_append`); the piece still fuses on its own. 14 s to 8 ms.

Apply when: changing `crates/ms-mir/src/opt/strfuse.rs` or adding a pass that rewrites a string `+` before `append_in_place` runs. Limited to loop-carried values: fusing a dying temporary into `concatN` is still right (one allocation).
Evidence: test `an_interpolated_append_in_a_loop_grows_the_accumulator_in_place`, bench `string.append_interpolated`.
Verify: `MS_EMIT_OPT=1 ms emit` shows one `string_append` and one `string_fmtN` in the loop.
