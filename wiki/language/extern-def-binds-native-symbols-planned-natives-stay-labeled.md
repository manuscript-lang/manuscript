[Wiki](../index.md) › [Language](index.md)

# `extern fn` binds native symbols; planned natives stay labeled

Decision: `extern fn name(...) T` declares a bodiless function whose symbol is its Manuscript name, linked with `--link` (#1136, #1138). It may be exported and may return `Result` with a payload-free error type; it cannot be generic, take defaults or `var` parameters, or be a method. Wrap an extern in an ordinary function to rename it. User externs cross only `Int`, `Float`, `Bool` and `String`; bundled modules may also declare generic externs and `extern type`. Binding C libraries such as libuv through a hardened C ABI (handles, sized types, events pulled as values) is proposed in [foreign functions](../../proposals/foreign-functions.md), not shipped. Planned and not shipped: `Weak[T]`, `Arena[T]` (#1133 marks them planned in the docs).


Apply when: adding natives or user-facing FFI; do not document planned items as available.
Evidence: [native functions](../../documentation/core-language/functions/native-functions.md), [extern parity script](../../scripts/extern-parity.py).
Verify: `extern fn labs(value: Int) Int` calls `labs`; a generic or method extern is rejected.
