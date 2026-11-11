[Wiki](../index.md) › [Runtime](index.md)

# File locks poll in Manuscript, and best-effort cleanup binds its Result

Verified: `FileHandle.try_lock` and `unlock` are the only native lock primitives (`File::try_lock`, `try_lock_shared` and `unlock` from Rust's standard library, which map to `flock` and `LockFileEx`, so no new crate or `unsafe`). The waiting `lock(exclusive, timeout)` is a loop of `try_lock` and a cancellable `sleep` in `fs.ms`, because a blocking native lock cannot be interrupted by task cancellation. The cross-platform `fs-atomic-lock-move.ms` fixture exercises these operations in the full CI matrix; a local Linux run alone does not validate native macOS or Windows behavior.

`Result.get(none)` on a `Unit!E` faults when the result is an error ("called Optional.get() on none"). Best-effort cleanup (removing a temporary file, shifting rotated logs whose older generations do not exist) binds the result instead: `_removed := remove(path, false)`. A rotating-log test that only passed on the first rotation caught this.

`write_atomic` preserves the mode exposed by `stat`. Unix retains numeric permission bits (the fixture requires `0600`); Windows exposes `0444` or `0666` according to the read-only attribute, so a writable file set to `0600` is reported as `0666` before and after replacement. Do not require Unix mode bits on Windows or skip the preservation assertion.

`fs.move` falls back to copy and remove only for the `Failed` error case, because the error type has no distinct cross-device case; other cases (`NotFound`, `PermissionDenied`) return unchanged. Add a dedicated case if the fallback ever needs to be narrower.

Apply when: adding locking, atomic replacement, rotation, or any best-effort cleanup in `.ms`.
Evidence: [fixture](../../tests/conformance/fixtures/e2e/stdlib/fs-atomic-lock-move.ms), [rotation test](../../tests/conformance/fixtures/e2e/stdlib/log.ms).
Verify: `target/release/ms test tests/conformance/fixtures/e2e/stdlib/fs-atomic-lock-move.ms`.
