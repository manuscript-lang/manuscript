[Wiki](../index.md) › [Standard-library design](index.md)

# Text in, bytes by explicit sibling

Decision: write-like operations accept `String`; the raw form is a `_bytes` sibling (`write_bytes`, `send_bytes`, `request_bytes`). Interface operations cannot be generic or overloaded, so sibling names carry the choice. Details and implementer obligations are in [runtime.md](../runtime/index.md).

Apply when: adding a stream, socket, file, or transport write.
Evidence: commits f42b47f1 and cd1ab831.
Verify: `stdout().write("text")` and `write_bytes(bytes)` both check (`ms check`); source `impl`s declare both.

---
Topics: [Standard-library API shape](../topics/stdlib-api-shape.md)
