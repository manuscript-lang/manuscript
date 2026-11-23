# Build f-strings in MIR

## Summary

- Problem: an f-string or `a + b + c` is one opaque runtime call (`msrt_string_fmt2`..`fmt6`, `concat2`..`concat6`, `append_fmt1`..`append_fmt5`) with the parts passed through a mask and up to six slots. The compiler knows every part and its type, the backend sees nothing across the call, and a longer text is split into chained groups of six.
- Change: lowering emits the join itself: format each Int into a stack slot, add the part lengths, make or grow the string once, copy each part. The runtime keeps three small primitives: make a string of a known length, grow an owned string by a known amount, write an Int in decimal into a buffer.
- Decision requested: build it as one PR (new MIR operations `str.data` and `mem.copy`, lowering, the append pass, deletion of the numbered entry points). No language change.

## Status

Baseline measured 2026-11-23 on `main` (Linux, shared VM, median of 5): `/tmp`-style microbenchmark of `s += f"{i}={i * 3};"` for 2M iterations plus 5M `f"item {i} of {n} at {i + 1}"` joins, about 320 to 440 ms (noisy). The build must not be slower than this baseline.

## Problem

`src/runtime/core/string_join.c` collects the parts into a fixed `Join` of six `MsSpan`s with 24 bytes of digit space each, then calls `msrt_string_join` or `msrt_string_append_parts`. `lower_text.c` picks the entry by part count and builds a bitmask of which parts are Ints; `opt_strfuse.c` rewrites a join whose first part is a dying owned string into `append_fmtN` by name. The consequences:

- Six is a cap in three places (lowering, runtime, pass); longer texts re-join the previous result.
- Every Int is formatted by the runtime inside the call, so a constant part length or an Int that is already a known width is not visible to LLVM.
- Part lengths are summed in a loop over an array although the count is known at compile time.

## Design

New MIR operations, general rather than string-specific:

1. `str.data s`: the address of the bytes of `s` (for an inline string, a frame slot the two words are written to, as `str.byte` already does).
2. `mem.copy dst src len`: `llvm.memcpy`, no overlap.

Runtime primitives (small, general):

- `msrt_string_open(total, out)`: writes a string of `total` bytes (inline when at most 15) and returns the address to fill; faults past the string limit like `concat`.
- `msrt_string_grow(s, extra, out)`: the owned `s` grown by `extra` bytes in place (with the existing spare-capacity growth), or a fresh copy when `s` is borrowed, inline or empty; returns the address of the first new byte.
- `msrt_int_format(v, buffer)`: writes decimal text, returns its length.

Lowering of `f"..."` with parts `p0..pn-1`:

1. Evaluate parts left to right. For each Int, `slot` of 20 bytes, `msrt_int_format`; its length is the result.
2. `total = sum(lengths)`, where a string part's length is `str.bytes` and a literal's is a constant.
3. `cursor = msrt_string_open(total, out)`, then for each part `mem.copy cursor, data, len; cursor += len`.

The append pass keeps its rule (the grown string dies at the call, used once) and emits `msrt_string_grow` for the first part instead of renaming a call; the other parts are copied after it. A part that is a view into the grown string cannot exist: the checker rejects moving a string while it is borrowed.

Deleted: `msrt_string_fmt2..6`, `append_fmt1..5`, the mask, `TEXT_MAX_JOIN`, and the name-keyed `fuse_extern`. `concat2..6` follow the same lowering and go in the same PR if the baseline allows; otherwise they stay and are listed as the follow-up.

## Alternatives considered

- Do nothing: the cap and opaque call stay; no measured loss today, so this is only worth it if the build is not slower.
- Variadic runtime entry taking an array of spans: removes the cap but keeps the opacity and still needs a stack array.
- Format Ints with a MIR digit loop: more code per site, LLVM does not do better than the runtime's two-digit table; keep `msrt_int_format`.

## Testing

Output identical on f-strings of every part kind (empty, literal, inline, owned, static, Int at its extremes), `+=` in a loop, strings past 15 and 2^31 bytes (fault text), and a join of more than six parts. The microbenchmark above before and after, and the string kernels, with a result no slower than the baseline. `make conform` with no new failures.
