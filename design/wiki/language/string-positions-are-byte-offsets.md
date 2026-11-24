[Wiki](../index.md) › [Language](index.md)

# String positions are byte offsets, with no scalar index

Decision (Chinmay, 2026-11-15, "rust style"): `String.length()`, `slice`, `view`, `index_of`, `last_index_of` and `scalar_at(offset, default)` all use UTF-8 byte offsets, so every position is O(1) and positions compose. `scalar_length()` is the O(n) scalar count. `get`, `take`, `drop` and `slice_scalars` are removed; walk characters with `chars()` or `scalars(text)`. A bound inside a scalar is `ERANGE` for `slice` and a fault for `view`. `pad_*` and `count("")` stay scalar-based.

Reason: an integer scalar index in UTF-8 is O(n) per access, which made every index loop quadratic on non-ASCII text and forced caches that go stale. Rejected: caching a scalar-index table per string (see `design/proposals/byte-offset-strings.md`).

Apply when: porting code that used scalar positions. Probe by renaming the String methods and running `ms check`; a position that crosses a mixed-script text silently changes meaning, so check expected fixtures.
