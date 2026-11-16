# Strings record their spare room

Status: approved by Chinmay on 2026-11-16 ("ptr, len, cap style? do it"); implemented in two stacked PRs.

## Problem

`s += piece` costs 111 instructions per append in a Release build (200k appends of `"ab"`: 32.0M instructions; the same loop in C with `realloc` doubling: 2.4M). Appending needs the room left in the block, and a string has no capacity: the runtime asks the allocator (`usable_size`, a page-table lookup) on every call, decodes the two-word tagged layout, and calls `memcpy` and `is_ascii`. Because the answer lives in the allocator, generated code cannot check it inline the way `StringBuilder.append` does, so every append is a runtime call.

## Design

The second word of an owned string holds the length in bits 0..30, since a string is at most 1 << 30 bytes. Bits 31..60 were always zero. They now hold the spare room: the bytes available after the text and its NUL.

- A recorded spare room is a lower bound. Zero means unknown, and the allocator stays the truth; every producer that builds a string with `StrVal::owned` records none, so nothing else changes.
- `msrt_string_append` uses the recorded room when it covers the piece and otherwise asks the allocator once, writing the answer back for the next append.
- Length reads mask 31 bits (`STR_LEN_MASK`); equality of two strings ignores the ASCII flag and, for non-inline strings, the spare room. Inline strings keep their bytes in the same bits, so the mask depends on the tag (`eq_differ`, `string_eq_call`).
- Stage two: a shared MIR fast path for `string_append`, written like the map probes in `rtinline.rs`, so both backends inline it: owned receiver, flat piece, room recorded, piece does not alias the receiver, short ASCII piece. Anything else calls the runtime.

## Evidence

Stage one alone: 36.4M to 31.8M on the 200k-append probe. The guard `bench/perf/guards/append` records the count for the nightly gate.

## Alternatives

- Three-word strings `{ptr, len, cap}`: changes the size of every string slot, list element and ABI struct; the free bits make the same information available with no layout change.
- Capacity in an allocation header: an extra load before the text and a layout change for every owned string.
- Leaving it: appends in loops stay 8 to 10 times C.
- Tightening the runtime function only: tried, 1.6% gain.

## Risks

Any code that edits the length of an owned string in place must also update or clear the room, or an append could write past the block. The runtime builds strings only through `StrVal::owned`, which records none; the `.tagged` field is not written elsewhere. A fixture (`string-spare-room-keeps-equality`) covers equality, hashing and map lookup of strings that carry room.
