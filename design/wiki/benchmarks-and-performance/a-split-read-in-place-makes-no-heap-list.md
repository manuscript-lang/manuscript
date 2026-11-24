# A split read in place makes no heap list

Verified (2026-11-23): `line.split(" ")` of a variable lowered to `msrt_string_split_view`, which allocates and frees a list per call. The runtime already had the two twins that avoid it (`msrt_string_split_first`, `msrt_string_split_view_into`), written for the Rust compiler's statement analyses, but the C lowering never called them, so split was 62% of `logstats`, 32% of `dedupe` and 34% of `grep`. The `splitview` MIR pass rewrites a call whose list is only read and dropped: `split_first` when only element 0 is read right after the call, `split_view_into` (eight strings in the frame, heap fallback for a longer text or more pieces) otherwise. Any other use of the list (call, store, return, block argument, `list.take`, `list.push`) keeps the heap call. `logstats` 913.8M to 600.5M instructions, `dedupe` 1789M to 1347M.

The twin is declared on the signature (`@twin=split_view`), not found by name. `find_byte` is `MS_ALWAYS_INLINE` because the exported wrapper gave it a second caller and the compiler stopped inlining it into `ms_needle_find`, which cost `grep` +2.6%.

Not done: the lazy iterator twin (`msrt_string_split_iter`) for `for piece in text.split(..)`, which changes the loop shape.

`get_or` on a map with a word value (`Map[String, Int]`, the counting idiom) is answered by the same inline probe as `get`: the role `MR_MAP_PROBE_*` now covers `msrt_map_get_or`, and `opt_probe` builds a helper that stores the stored word or the fallback to the result slot. `csvgroup` -4.8% instructions. A struct value (`Map[String, Total]`) still calls the runtime: MIR has no type size to stride the slots by.

Apply when: a program that parses lines is dominated by `msrt_string_split_view`, or a new borrowing runtime function has a twin that skips building its result.
