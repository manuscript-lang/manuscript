import Closeable from "@std/core.ms"
import ReadStream, WriteStream, Source, Sink, stream, writer from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import Promise, deferred, complete from "@std/concurrency/promise.ms"
import TlsOptions from "@std/net/tls.ms"
import (
    msstd_websocket_close,
    msstd_websocket_share,
    msstd_websocket_close_if_last,
    msstd_websocket_ping,
    msstd_websocket_ping_bytes,
    msstd_websocket_receive,
    msstd_websocket_send_bytes,
    msstd_websocket_subprotocol
) from "@std/internal/net.ms"

// The runtime handle behind a `RawWebSocket`.
export extern type NativeWebSocket

// The native WebSocket a handshake returns; it is wrapped into a `WebSocket`.
export type RawWebSocket:
    // The runtime handle; it is released when the last end closes.
    native: NativeWebSocket

// The kind of a WebSocket message.
export enum WebSocketKind:
    Text  // A text frame: the payload is valid UTF-8.
    Binary  // A binary frame: the payload is arbitrary bytes.
    Ping  // A ping control frame, at most 125 bytes; written only, the peer's pongs are answered automatically.

// One WebSocket message.
export type WebSocketMessage:
    // The payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    // Whether the message is text or binary, or a ping.
    kind: WebSocketKind

// A message as the native layer reports it.
export type RawWebSocketMessage:
    // The payload bytes; for a text frame they are the UTF-8 encoding of the text.
    data: Bytes
    // True for a text frame, false for a binary frame.
    text: Bool

type WebSocketSource:
    raw: RawWebSocket

impl Source[WebSocketMessage] for WebSocketSource:
    // Waits for the next complete message; none once the peer closes normally.
    // A larger message is `EOVERFLOW` and a malformed text message `EBADMSG`; after any failure the connection is closed.
    var fn next() WebSocketMessage?!:
        let raw = try msstd_websocket_receive(self.raw.native)

        if let message = raw:
            var kind = WebSocketKind.Binary
            if message.text:
                kind = WebSocketKind.Text
            return ok(WebSocketMessage(message.data, kind))

        return ok(none)

    var fn close() Unit!:
        msstd_websocket_close_if_last(self.raw.native)
        return ok(unit)

type WebSocketSink:
    raw: RawWebSocket

impl Sink[WebSocketMessage] for WebSocketSink:
    // Sends one message. Text must be valid UTF-8 or the call returns EBADMSG, and a payload over `max_message_bytes` returns EOVERFLOW.
    var fn put(value: WebSocketMessage) Unit!:
        match value.kind:
            Text: return msstd_websocket_send_bytes(self.raw.native, value.data, true)
            Binary: return msstd_websocket_send_bytes(
                self.raw.native, value.data, false
            )
            Ping: return msstd_websocket_ping_bytes(self.raw.native, value.data)

    var fn drain() Promise[Unit]:
        return deferred[Unit](fn(id: Int) Unit: complete[Unit](id, ok(unit)))

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        msstd_websocket_close_if_last(self.raw.native)
        return ok(unit)

/*
A WebSocket connection: `input` reads whole messages and `output` writes them. Move the streams to different tasks to
receive and send at once. The connection closes, after a normal-closure frame, when both streams are closed, which is
also what closing the `WebSocket` does.
*/
export type WebSocket:
    // Messages from the peer; none once the peer closes normally.
    input: ReadStream[WebSocketMessage]
    // Messages to the peer.
    output: WriteStream[WebSocketMessage]
    // The subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    subprotocol: String

impl Closeable for WebSocket:
    // Closes both streams, and with them the connection.
    var fn close() Unit!:
        try self.input.close()
        return self.output.close()

// Wraps a native WebSocket into a `WebSocket`.
export fn web_socket_from(raw: RawWebSocket) WebSocket:
    let subprotocol = msstd_websocket_subprotocol(raw.native)
    let other = RawWebSocket(msstd_websocket_share(raw.native))
    return WebSocket(
        input: stream[WebSocketMessage](WebSocketSource(raw)),
        output: writer[WebSocketMessage](WebSocketSink(other)), subprotocol: subprotocol
    )

// WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    // Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Int?
    // Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Duration?
    // TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    // When True, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool
