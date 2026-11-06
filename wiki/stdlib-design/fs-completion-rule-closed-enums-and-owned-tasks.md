[Wiki](../index.md) › [Standard-library design](index.md)

# fs completion rule, closed enums and the owned-task pattern

Decision: in `@std/os/fs.ms`, operations on whole file contents (`read_file`, `write_file`, `append_file`, `write_atomic`) return `Promise`; every other operation blocks and returns a `Result`. Modes, origins and kinds are enums, not strings or bool piles: `OpenMode`, `Seek`, `FileKind` (one `kind` field on `FileInfo`, with `is_file()`, `is_directory()`, `is_symlink()`), `CloneMode`. `stat` follows links by default. A function takes at most three parameters before an `*Options` record. `Directory` is a stream `Source[DirectoryEntry]`.

A promise-returning wrapper uses `owned_task(job(path.clone(), ...))`, where `job` is a function that returns the closure; a returned closure owns its captures, while a closure literal passed to a promise call is borrowed and rejected. Release a write-slot permit inside the closure as a local (`let permit = WritePermit(held: held)`): a captured permit only closes when the promise handle drops, and the task runs at once, so parked callers would deadlock on the pool.

Apply when: adding or changing an fs operation, or any wrapper that must hand an owned value to a promise.
Evidence: `tests/e2e/testdata/stdlib/fs-write-backpressure.ms` hangs if the permit is held by a captured resource; `stdlib/os/fs.ms`.
Verify: `ms test tests/e2e/testdata/stdlib/fs-write-backpressure.ms` passes in under a second.
