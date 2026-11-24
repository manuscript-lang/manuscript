[Wiki](../index.md) › [Runtime](index.md)

# An extern declared `T!` is a native with a u8 status and trailing out slots

Decided: a native called as `extern fn f(args) T!` returns a `u8` status (`src/abi/status.h`, 0 is ok) and writes the ok payload through a trailing `out` address and, when it can explain itself, a message through a last `err ErrSlot` string. Lowering (`fn_status_call`, `lower_native.c`) allocates the slots, calls the native, and builds `ok(payload)` or `error(Error)`. The `Error` comes from the stdlib function `msstd_status_error` in `src/stdlib/core/core.ms`: kind and words per status, `<domain>: <words>`, the native's text appended after a colon, and `-` words meaning the native's text is the whole message. The domain is the `@domain=` tag of the native's `ms-sig` comment.

Apply when: adding a fallible native (declare `-> u8` and `@domain=`, put `out` before `err`, set the err string only on failure) or a status code (add it to `status.h`, `status_kind` and `status_words`).
Rules: keep the status table in `.ms`, not in lowering. A module that words a status differently is a special case in `msstd_status_error` (filesystem not-found today); the Rust era read `// ms: words` comments instead.
Evidence: [lower_native.c](../../../src/compiler/lower/lower_native.c), [core.ms](../../../src/stdlib/core/core.ms), [status.h](../../../src/abi/status.h).
Verify: `BigInt.divide` by zero gives `big integer: invalid input` with kind `EINVAL`; `canonicalize("/nonexistent/file")` gives `filesystem: file or directory not found: /nonexistent/file`.
