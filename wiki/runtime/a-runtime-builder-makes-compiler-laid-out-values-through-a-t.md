[Wiki](../index.md) › [Runtime](index.md)

# A runtime builder makes compiler-laid-out values through a thunk, not a copy of the layout

Decided: an untyped `parse` builds `JsonValue` in the C tree builder (`src/runtime/std/json_tree.c`) while the scanner runs, with no document. The runtime never learns the alternative's layout: the compiler passes the type descriptor (value size, drop) and one generated thunk, `ctor(kind, payload, out)`, that moves a `Bool` byte, `String`, list or `String`-keyed map payload into a value of that case.

Apply when: adding another recursive alternative to build natively, or changing the `JsonValue` cases (the thunk looks them up by name) or the map/list slot layout.
Evidence: [builder and walker](../../src/runtime/std/json_tree.c), [thunk and call](../../crates/ms-lower/src/json.rs) (`json_tree_ctor`), [scanner](../../src/runtime/std/json_scan.c) (one scanner, two sinks: the document and the builder), [fixture](../../tests/conformance/fixtures/e2e/stdlib/json.ms) ("releases partial trees on failure").
The writer's walk copies a map's header when it opens it and keeps no pointer into the view thunk's frame: a thunk may pass the address of a local copy. Verify: `make c-test` (`src/runtime/tests/json_test.c` replays `src/runtime/tests/oracle/json.tsv`, recorded from Go); `ms run bench/tools/json_bench.ms`; the json fixtures pass; a failing document leaves no leak (`make leak-check`).
