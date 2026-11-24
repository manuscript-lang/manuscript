[Wiki](../index.md) › [Standard-library design](index.md)

# Text in, bytes by explicit sibling

Decision: write-like operations that are not streams accept `String`; the raw form is a `_bytes` sibling (`send_bytes`, `request_bytes`). Files are the exception: `write_file`, `append_file`, `write_atomic`, `FileHandle.write` and `write_at` take the `Writable` interface (`String` and `Bytes` implement it), so there are no `_bytes` file pairs. Add `Writable` rather than a sibling when an operation is a plain module function or a method on a concrete type; keep siblings for interface operations, which cannot take an interface-typed argument generically. Stream writes do not need one: `WriteStream[T]` is generic, so bytes go to a `WriteStream[Bytes]` (`stdout_bytes()`). Interface operations cannot be generic or overloaded, so sibling names carry the choice. Details and implementer obligations are in [runtime.md](../runtime/index.md).


Apply when: adding a socket, file, or HTTP write that is not a `WriteStream`.
Evidence: commits f42b47f1 and cd1ab831.
Verify: `stdout().write("text")` and `stdout_bytes().write(bytes)` both check (`ms check`).
