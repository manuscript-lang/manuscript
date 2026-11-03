[Wiki](../index.md) › [Runtime](index.md)

# Write operations take String; `_bytes` siblings take Bytes

Decision: stream writes are generic, `WriteStream[T].write(value: T)`, so there is no `write_bytes` on streams: `stdout()` is `WriteStream[String]` and `stdout_bytes()` shares its buffer as `WriteStream[Bytes]`. Operations that are not streams (`write_file`, `append_file`, `write_at`) accept `String`; raw bytes use a sibling named `<name>_bytes`. Network sends follow the same shape: `DatagramSocket.send`/`send_bytes`, `WebSocket.send`/`send_bytes(data, text: False)`, `ping`/`ping_bytes`, and `request`/`request_bytes` for the body. Interface operations cannot be generic or overloaded, so two names express the choice.

Apply when: adding or changing a write-like standard operation, or implementing `Sink`/`Transform` in source.
Evidence: user request in the project thread; [io](../../stdlib/io/io.ms), [fs](../../stdlib/os/fs.ms), [stream support](../../tests/e2e/testdata/stdlib/support/streams.ms).
Verify: `stdout().write("text")` and `stdout_bytes().write(bytes)` both type-check (`ms check`).
