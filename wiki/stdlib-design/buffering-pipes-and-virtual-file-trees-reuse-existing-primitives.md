[Wiki](../index.md) › [Standard-library design](index.md)

# Buffering, pipes and virtual file trees reuse existing primitives

Decision (Go-parity sweep, capability not API): line and delimiter reading is `lines`/`split` in `@std/io/streams.ms` over `ReadStream[Bytes]` (`BufferedReader`, `BufferedWriter` and `Scanner` are gone; write buffering is built into every `WriteStream`); an in-memory pipe is `pipe[T]`; a section reader is read over `read_at`; the virtual file system is the small `FileTree` interface (`read`, `children`) in `@std/os/tree.ms` with `host_tree`, `MemoryTree` and `walk`. Mutation stays off the interface, so write-side fakes are the concrete `MemoryTree`.
Decision (2026-11-02): `embed` is an `ms.toml` `[embed]` table, not a built-in. The driver generates a module whose `files()` returns a `MemoryTree` (base64 literals); the build cache stamps the directory and its files because it never hashes source ([proposal](../../proposals/embed.md)).

Apply when: adding stream wrappers, test file systems, or Go `io`/`bufio`/`io/fs` equivalents.
Evidence: [streams.ms](../../stdlib/io/streams.ms), [tree.ms](../../stdlib/os/tree.ms), [tests](../../tests/e2e/testdata/stdlib/tree.ms).
Verify: `ms test tests/e2e/testdata/stdlib/{streams,tree}.ms`.
