[Wiki](../index.md) › [Standard-library design](index.md)

# One spelling per operation; consolidate by domain

Decision: the stdlib reorganization (#659) removed duplicate routes: `cli` moved into `process` (`process.arguments`, `process.control().environment()` is the only environment API), the temp-root query moved to `FileSystem.temporary_root` (`fs` is the only temp-dir API), string-typed `crypto.hmac` was dropped for `HashAlgorithm.hmac`, and the SSE decoder became an interface with `feed`/`finish`/`retry` methods.

Apply when: adding or moving a stdlib function, or when two modules could both own an operation.
Evidence: commit 9a2dc4e6, [process](../../stdlib/os/process.ms), [fs](../../stdlib/os/fs.ms), [crypto](../../stdlib/crypto.ms), [sse](../../stdlib/net/sse.ms).
Verify: `ms search_symbol <old name>` finds no declaration; `make docs-check` passes and every moved symbol has an updated fixture.
