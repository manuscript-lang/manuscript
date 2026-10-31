[Wiki](../index.md) › [Runtime](index.md)

# Small map slots are copied inline, not by `memcpy`

Verified: the map insert copied a 72-byte `JsonValue` slot through a `memcpy` call per entry; sizes up to ten words now copy inline (`copy_slot`). Check the slot size of a new element type before assuming it is covered.

Apply when: a map or list of records shows `memcpy` in a profile.
Evidence: [map slots](../../crates/ms-rt/src/map.rs).
Verify: callgrind on `bench/perf/json` (`ms build bench/perf/json/ms.toml -o /tmp/jb`, then `valgrind --tool=callgrind /tmp/jb quick twitter:parse`).
