[Wiki](../index.md) › [Language](index.md)

# `extern def` binds native symbols; planned natives stay labeled

Decision: `extern def name(...) -> T` declares a bodiless function whose symbol is its Manuscript name, linked with `--link` (#1136, #1138). It may be exported and may return `Result` with a payload-free error type; it cannot be generic, take defaults or `var` parameters, or be a method. Wrap an extern in an ordinary function to rename it. Planned and not shipped: `extern type` and source-level `Shared[T]`, `Weak[T]`, `Arena[T]` (#1133 marks them planned in the docs).

Apply when: adding natives or user-facing FFI; do not document planned items as available.
Evidence: [native functions](../../documentation/core-language/functions/native-functions.md), [extern parity script](../../scripts/extern-parity.py).
Verify: `extern def labs(value: Int) -> Int` calls `labs`; a generic or method extern is rejected.
