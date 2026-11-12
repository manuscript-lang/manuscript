[Wiki](../index.md) › [Standard-library design](index.md)

# fs completion rule, closed enums and the owned-promise pattern

Decision: in `@std/os/fs.ms`, operations on whole file contents (`read_file`, `write_file`, `append_file`, `write_atomic`) return `Promise`; every other operation blocks and returns a `Result`. Modes, origins and kinds are enums, not strings or bool piles: `OpenMode`, `Seek`, `FileKind` (one `kind` field on `FileInfo`, with `is_file()`, `is_directory()`, `is_symlink()`), `CloneMode`. `stat` follows links by default. A function takes at most three parameters before an `*Options` record. `Directory` is a stream `Source[DirectoryEntry]`.

A promise-returning wrapper binds `owned := path.clone()` and returns `promise(fn: work(owned, ...), options: PromiseOptions(placement: Placement.Here))`; a returned promise owns its closure's captures, so no `owned_task` or job-returning function is needed. Release a write-slot permit inside the work function as a local (`permit := WritePermit(held: held)`): a captured permit only closes when the promise handle drops, and the task runs at once, so parked callers would deadlock on the pool.

Apply when: adding or changing an fs operation, or any wrapper that must hand an owned value to a promise.
Evidence: `tests/conformance/fixtures/e2e/stdlib/fs-write-backpressure.ms` hangs if the permit is held by a captured resource; `stdlib/os/fs.ms`.
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/fs-write-backpressure.ms` passes in under a second.
