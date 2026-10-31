[Wiki](../index.md) › [Runtime](index.md)

# Closeable.close() returns a Result

Decision (Chinmay): there is one `Closeable` interface and `close()` returns `Unit!` (`Result[Unit, Error]`), so a failed flush or release is a value. An implicit scope-end close never drops its error: it becomes the function's error, or the close faults when nothing can carry it (non-`Result` function, a holder's part, a replaced or temporary value). Types whose release cannot fail return `ok(unit)`. Resource `clone()` is fallible; only plain-data types are `Clonable`.

Apply when: implementing `Closeable`, writing cleanup, or changing scope-end drops.
Evidence: [stdlib/core.ms](../../stdlib/core.ms), [fallible-close proposal](../../proposals/fallible-close.md), [closeable guide](../../documentation/core-language/cleanup/closeable.md).
Verify: a `close()` error in a `Result` function propagates; in a non-`Result` function it faults rather than being ignored.

---
Topics: [Cleanup and resources](../topics/cleanup-and-resources.md) · [Errors and results](../topics/errors-and-results.md)
