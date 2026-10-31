[Wiki](../index.md) › [Runtime](index.md)

# A runtime builder makes compiler-laid-out values through a thunk, not a copy of the layout

Decided: an untyped `parse` builds `JsonValue` in `ms_rt::tree::TreeBuilder` while the scanner runs, with no document. The runtime never learns the alternative's layout: the compiler passes the type descriptor (value size, drop) and one generated thunk, `ctor(kind, payload, out)`, that moves a `Bool` byte, `String`, list or `String`-keyed map payload into a value of that case. Completed values wait on one stack of `size` bytes each; closing a container moves its children into a list or builds the map with the ordinary map insert, which also rejects repeated keys. A failed parse drops what the stack still holds. The typed decoders still read the document.

Apply when: adding another recursive alternative to build natively, or changing the `JsonValue` cases (the thunk looks them up by name) or the map/list slot layout.
Evidence: [builder](../../crates/ms-rt/src/tree.rs), [thunk and call](../../crates/ms-lower/src/json.rs) (`json_tree_ctor`), [scanner](../../crates/ms-std-json/src/lib.rs) (`parse_tree`), [fixture](../../tests/e2e/testdata/stdlib/json.ms) ("releases partial trees on failure").
Verify: `sh bench/perf/json/run.sh`; the json fixtures pass; a failing document leaves no leak (`make leak-check`).

---
Topics: [Build and CI](../topics/build-and-ci.md)
