[Wiki](../index.md) › [Language](index.md)

# `extern fn` binds native symbols; planned natives stay labeled

Decision: `extern fn name(...) T` declares a bodiless function whose symbol is its Manuscript name, linked with `--link` (#1136, #1138). It may be exported; it cannot be generic, take defaults or `var` parameters, or be a method. Wrap an extern in an ordinary function to rename it. User externs follow `ms_abi.h` v1: sized numbers at their C width, `Bool`, `String`, `Bytes`, `List` of those, user `extern type` handles made by `ms_object_new`, and `Result` whose error cases carry nothing, `code: Int` or `message: String`. Every output is pre-filled with an empty value and dropped after the call, so a shim that skips or mis-writes one causes no undefined drop; a NULL object or an unknown status faults. Callbacks, calls from other threads, blocking work, sockets, stop hooks and per-isolate state are stage 2 of [foreign functions](../../proposals/foreign-functions.md), not shipped. Planned and not shipped: `Weak[T]`, `Arena[T]` (#1133 marks them planned in the docs).


Apply when: adding natives or user-facing FFI; do not document planned items as available.
Evidence: [native functions](../../documentation/core-language/functions/native-functions.md), [ABI round trip](../../crates/ms-cli/tests/extern_link.rs).
Verify: `cargo test -p ms-cli --test extern_link` round-trips every signature type on both backends; a generic or method extern is rejected.
