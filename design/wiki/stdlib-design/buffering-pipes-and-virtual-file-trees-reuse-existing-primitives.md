[Wiki](../index.md) › [Standard-library design](index.md)

# Buffering, pipes and virtual file trees reuse existing primitives

Decision (Go-parity sweep, capability not API): line and delimiter reading is `lines`/`split` in `@std/io/steps.ms` over `ReadStream[Bytes]` (`BufferedReader`, `BufferedWriter` and `Scanner` are gone; write buffering is built into every `WriteStream`); an in-memory pipe is `pipe[T]`; a section reader is read over `read_at`; the virtual file system is the small `FileTree` interface (`read`, `children`) in `@std/os/tree.ms` with `host_tree`, `MemoryTree` and `walk`. Mutation stays off the interface, so write-side fakes are the concrete `MemoryTree`.
Decision (2026-11-02): `embed` is an `ms.toml` `[embed]` table, not a built-in. The driver generates a module whose `files()` returns a `MemoryTree` (base64 literals); the build cache stamps the directory and its files because it never hashes source ([proposal](../../proposals/embed.md)).

Verified (2026-11-18): `HostTree` once followed a symbolic link out of its root (`..` was rejected only lexically), so a link under the root read any file. `read` and `children` now canonicalize the path and the root and return `EINVAL` outside the root; links that stay inside still work. The check is not atomic with the read, so a hostile writer racing the check can still win.

Apply when: adding stream wrappers, test file systems, or Go `io`/`bufio`/`io/fs` equivalents.
Evidence: [streams.ms](../../../src/stdlib/io/streams.ms), [tree.ms](../../../src/stdlib/os/tree.ms), [tests](../../../tests/lang/stdlib/tree.ms).
Verify: `ms test tests/lang/stdlib/{streams,tree}.ms`.
