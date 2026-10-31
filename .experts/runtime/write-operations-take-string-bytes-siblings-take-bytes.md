[Wiki](../index.md) › [Runtime](index.md)

# Write operations take String; `_bytes` siblings take Bytes

Decision: write APIs (`write`, `write_file`, `append_file`, `write_at`, on streams, files, connections, transports) accept `String`; raw bytes use a sibling named `<name>_bytes` (`write_bytes`, `write_file_bytes`). Network sends follow the same shape: `DatagramSocket.send`/`send_bytes`, `WebSocket.send`/`send_bytes(data, text: False)`, `ping`/`ping_bytes`, and `request`/`request_bytes` for the body. Interface operations cannot be generic or overloaded, so two names express the choice. Any source `impl` of `WriteStream` or `Transport` must declare both; implementing `write` as `self.write_bytes(data.to_bytes())` keeps one body.

Apply when: adding or changing a write-like standard operation, or implementing `WriteStream`/`Transport` in source.
Evidence: user request in the project thread; [io](../../stdlib/io.ms), [fs](../../stdlib/fs.ms), [stream support](../../tests/e2e/testdata/stdlib/support/streams.ms).
Verify: `stdout().write("text")` and `write_bytes(bytes)` both type-check (`ms check`).

---
Topics: [Standard-library API shape](../topics/stdlib-api-shape.md)
