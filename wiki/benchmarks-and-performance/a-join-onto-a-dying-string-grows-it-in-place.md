[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A join onto a dying string grows it in place

Verified (2026-11-14, #3879): `s += f"item-{i},"` in a loop took 14 s for 200k appends in Release builds. A join with `s` as its first part copies the whole prefix each iteration.

Rule (2026-11-16): lowering joins every piece of `s + a + f"{b}{n}"` into one call with no special case for an accumulator. `strfuse::append_in_place` then turns any concat or join whose first part is an owned string that dies right after into its growing twin (`string_append`, `string_append_fmtN`), in Debug and Release. The twin writes the parts straight onto `s`, so no temporary text exists: 1,018 to 575 instructions per item for `out += f"\{\"id\":{i},\"name\":\"item-{i}\"\}"`.

Apply when: changing how lowering joins text (`crates/ms-lower/src/text.rs`) or `crates/ms-mir/src/opt/strfuse.rs`. Do not add a lowering case keyed on the assigned name; a new join shape needs a growing twin the pass can pick, or the loop is quadratic.
Evidence: tests `a_join_onto_a_dying_string_grows_it_in_place`, `append_parts_grows_an_owned_string_and_joins_onto_any_other`, fixture `string-grows-from-a-join`, bench `string.append_interpolated`.
Verify: `MS_EMIT_OPT=1 ms emit` shows one `string_append_fmtN` in the loop and no `string_fmtN`.
