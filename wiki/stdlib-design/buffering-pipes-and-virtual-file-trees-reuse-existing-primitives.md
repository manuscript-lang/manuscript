[Wiki](../index.md) › [Standard-library design](index.md)

# Buffering, pipes and virtual file trees reuse existing primitives

Decision (Go-parity sweep, capability not API): buffered reader/writer and `Scanner` live in `@std/io/buffered.ms` as plain `.ms` over `ReadStream`/`WriteStream`; an in-memory pipe is `channel_reader`/`channel_writer` over a task `Channel[_, Bytes]` (no separate pipe type, no new runtime primitive); a section reader is `section(file, offset, length)` over `read_at`; the virtual file system is the small `FileTree` interface (`read_file`, `list`) in `@std/os/tree.ms` with `host_tree`, `MemoryTree` and `walk`. Mutation stays off the interface, so write-side fakes are the concrete `MemoryTree`.
Open: `embed` (compile-time file embedding) needs a language decision from the owner before any design.

Apply when: adding stream wrappers, test file systems, or Go `io`/`bufio`/`io/fs` equivalents.
Evidence: [buffered.ms](../../stdlib/io/buffered.ms), [tree.ms](../../stdlib/os/tree.ms), [tests](../../tests/e2e/testdata/stdlib/tree.ms).
Verify: `ms test tests/e2e/testdata/stdlib/{buffered,streams,tree}.ms`.
