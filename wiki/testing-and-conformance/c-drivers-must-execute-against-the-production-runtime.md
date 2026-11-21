[Wiki](../index.md) › [Testing and conformance](index.md)

# C drivers must execute against the production runtime

Verified: the native C smoke harness compiled and linked with obsolete one-word string return/message declarations, then aborted at its first call. The adjacent benchmark also retained a six-word map after `MapVal` grew to seven words. Successful linking cannot check C declarations against Rust exports.

The generated `ms_str_len` mask must come from `STR_LEN_MASK`, including exclusion of the ASCII flag. Header freshness alone missed a literal mask that counted that flag as length. `extern_link::c_string_lengths_exclude_metadata_on_both_backends` passes actual literals, inline text, owned ASCII, clones, views, NUL and Unicode through a C shim.

Apply when: changing runtime value layouts or exported signatures. Use the canonical [C string header](../../crates/ms-rt-abi/include/ms_abi.h), audit the remaining declarations against `ms-rt-abi`, and keep the production archive driver in the regular test suite.
Evidence: the Rust smoke and benchmark harnesses (`crates/ms-native/tests/c_smoke.rs`, `crates/ms-rt/tests/`) were deleted with the runtime flip (2026-11-20): the runtime is C, so `make c-test` (src/runtime/tests, built with ASan and UBSan against the real sources) and the conformance corpus are the checks that execute C declarations against the production runtime.
