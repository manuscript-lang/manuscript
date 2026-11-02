[Wiki](../index.md) › [Runtime](index.md)

# File locks poll in Manuscript, and best-effort cleanup binds its Result

Verified: `FileHandle.try_lock` and `unlock` are the only native lock primitives (`File::try_lock`, `try_lock_shared` and `unlock` from Rust's standard library, which map to `flock` and `LockFileEx`, so no new crate or `unsafe`). The waiting `lock(exclusive, timeout)` is a loop of `try_lock` and a cancellable `sleep` in `fs.ms`, because a blocking native lock cannot be interrupted by task cancellation. Linux is exercised by `fs-atomic-lock-move.ms`; macOS and Windows are covered by the standard library mapping and the full CI matrix, not by a local run.

`Result.get(none)` on a `Unit!E` faults when the result is an error ("called Optional.get() on none"). Best-effort cleanup (removing a temporary file, shifting rotated logs whose older generations do not exist) binds the result instead: `let _removed = remove(path, false)`. A rotating-log test that only passed on the first rotation caught this.

`fs.move` falls back to copy and remove only for the `Failed` error case, because the error type has no distinct cross-device case; other cases (`NotFound`, `PermissionDenied`) return unchanged. Add a dedicated case if the fallback ever needs to be narrower.

Apply when: adding locking, atomic replacement, rotation, or any best-effort cleanup in `.ms`.
Evidence: [fixture](../../tests/e2e/testdata/stdlib/fs-atomic-lock-move.ms), [rotation test](../../tests/e2e/testdata/stdlib/log.ms).
Verify: `target/release/ms test tests/e2e/testdata/stdlib/fs-atomic-lock-move.ms`.
