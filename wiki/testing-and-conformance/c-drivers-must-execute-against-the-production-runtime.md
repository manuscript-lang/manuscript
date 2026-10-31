[Wiki](../index.md) › [Testing and conformance](index.md)

# C drivers must execute against the production runtime

Verified: the native C smoke harness compiled and linked with obsolete one-word string return/message declarations, then aborted at its first call. The adjacent benchmark also retained a six-word map after `MapVal` grew to seven words. Successful linking cannot check C declarations against Rust exports.


Apply when: changing runtime value layouts or exported signatures. Use the canonical [C string header](../../crates/ms-rt-abi/include/ms_abi.h), audit the remaining declarations against `ms-rt-abi`, and keep the production archive driver in the regular test suite.
Evidence: [C driver regression](../../crates/ms-native/tests/c_smoke.rs), [smoke checks](../../crates/ms-rt/tests/e2e/run.sh).
Verify: `cargo nextest run -p ms-native --test c_smoke` exercises strings, faults, guard messages, joins, cancellation, argument lists, profiling, and the adjacent benchmark's results on Linux. Other native hosts retain their existing runtime and generated-program tests.
