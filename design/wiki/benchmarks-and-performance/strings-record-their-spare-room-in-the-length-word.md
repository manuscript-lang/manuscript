[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Strings record their spare room in the length word

Verified (2026-11-16, `design/proposals/string-spare-room.md`): an owned string keeps its length in bits 0..30 of the second word and the spare room after its text in bits 31..60 (`STR_LEN_MASK`, `STR_SPARE_MASK`, `StrVal::spare`/`with_spare`). The room is a lower bound, zero means unknown, and `msrt_string_append` falls back to `usable_size` and records the answer.

- Never hardcode a length mask: `(1 << 61) - 1` read the room as length. The masks in `rtinline.rs`, `rtstr.rs`, both backends and the C header and debugger script now use the ABI constants.
- String equality by tagged word must mask the spare room for owned strings only; an inline string keeps its bytes in those bits. `eq_differ` (LLVM) and `string_eq_call` (Cranelift) select the mask by tag.
- Build owned strings with `StrVal::owned`, which records no room. Writing `tagged` directly after growing a string in place would let the next append write past the block.

## The inline append (stage two)

`opt/appendfast.rs` rewrites each `string_append` into a call of one generated `inline(always)` function, then the inliner runs again. The fast path needs an owned receiver with recorded room, a piece of 1 to 16 bytes that is inline or flat and not inside the receiver's text, and an ASCII flag that stays true; it writes the bytes with the new `ptr.storeu` op (overlapping 8, 4 or 1 byte stores), the NUL and the length word. Anything else calls `msrt_string_append`. `s += "ab"` 200k times: 32.0M to 5.0M instructions (C 2.4M).

- A literal must carry the ASCII flag or a flagged receiver always takes the slow path (the first version measured no gain because `"ab"` was unflagged). Both backends now flag ASCII literals; `str.ascii_len` of a long literal answers its length.
- Keep the reads of the two strings' address words as `int` for the overlap compare and as `ptr` for the copy: comparing a `ptr` with an `int` panics the LLVM builder.
- `put`/`take` of the receiver through a slot is safe from `put_takes`, which stops at any impure instruction or use of the slot.
