[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Strings record their spare room in the length word

Verified (2026-11-16, `proposals/string-spare-room.md`): an owned string keeps its length in bits 0..30 of the second word and the spare room after its text in bits 31..60 (`STR_LEN_MASK`, `STR_SPARE_MASK`, `StrVal::spare`/`with_spare`). The room is a lower bound, zero means unknown, and `msrt_string_append` falls back to `usable_size` and records the answer.

- Never hardcode a length mask: `(1 << 61) - 1` read the room as length. The masks in `rtinline.rs`, `rtstr.rs`, both backends and the C header and debugger script now use the ABI constants.
- String equality by tagged word must mask the spare room for owned strings only; an inline string keeps its bytes in those bits. `eq_differ` (LLVM) and `string_eq_call` (Cranelift) select the mask by tag.
- Build owned strings with `StrVal::owned`, which records no room. Writing `tagged` directly after growing a string in place would let the next append write past the block.
