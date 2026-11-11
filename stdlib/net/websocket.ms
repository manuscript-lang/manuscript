import (
	Bytes from "@std/bytes.ms",
	Promise, complete, deferred from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	ReadStream, Sink, Source, WriteStream from "@std/io/io.ms",
	HttpHeaders, headers from "@std/net/http.ms",
	TlsOptions from "@std/net/tls.ms",
	Duration from "@std/time.ms",

	msstd_websocket_close,
	msstd_websocket_close_if_last,
	msstd_websocket_ping,
	msstd_websocket_ping_bytes,
	msstd_websocket_receive,
	msstd_websocket_send_bytes,
	msstd_websocket_share,
	msstd_websocket_subprotocol from "@std/internal/net.ms",
)

// The runtime handle behind a `WebSocket`.
export extern type NativeWebSocket

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
	native: NativeWebSocket

// Waits for the next complete message; none once the peer closes normally.
// A larger message is `EOVERFLOW` and a malformed text message `EBADMSG`; after any failure the connection is closed.
fn var WebSocketSource.next() WebSocketMessage?!:
	raw := msstd_websocket_receive(self.native)?

	if message := raw:
		kind := if message.text: WebSocketKind.Text else: WebSocketKind.Binary
		return ok(WebSocketMessage(message.data, kind))

	return ok(none)

fn var WebSocketSource.close() Unit!:
	msstd_websocket_close_if_last(self.native)

type WebSocketSink:
	native: NativeWebSocket

// Sends one message. Text must be valid UTF-8 or the call returns EBADMSG, and a payload over `max_message_bytes` returns EOVERFLOW.
fn var WebSocketSink.write(value: WebSocketMessage) Unit!:
	match value.kind:
		Text: return msstd_websocket_send_bytes(self.native, value.data, true)
		Binary: return msstd_websocket_send_bytes(self.native, value.data, false)
		Ping: return msstd_websocket_ping_bytes(self.native, value.data)

fn var WebSocketSink.flush() Unit!:
	return ok(unit)

fn var WebSocketSink.close() Unit!:
	msstd_websocket_close_if_last(self.native)

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

// Closes both streams, and with them the connection.
fn var WebSocket.close() Unit!:
	self.input.close()?
	return self.output.close()

// Wraps a native WebSocket into a `WebSocket`.
export fn web_socket_from(native: NativeWebSocket) WebSocket:
	subprotocol := msstd_websocket_subprotocol(native)
	other := msstd_websocket_share(native)
	return WebSocket(
		input: ReadStream[WebSocketMessage](WebSocketSource(native)),
		output: WriteStream[WebSocketMessage](WebSocketSink(other)),
		subprotocol: subprotocol
	)

// What a WebSocket client connection is opened with: headers, subprotocols, message bound, time budget, TLS settings and compression.
export type WebSocketOptions:
	// Extra handshake headers. `Upgrade`, `Connection`, `Host` and `Sec-WebSocket-*` cannot be set.
	headers: HttpHeaders = headers()
	// Subprotocols to offer, in preference order.
	subprotocols: List[String] = []
	// Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
	max_message_bytes: Int? = none
	// Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
	timeout: Duration? = none
	// TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
	tls: TlsOptions = TlsOptions()
	// When True, offers per-message compression during the handshake; it applies only if the peer agrees.
	compression: Bool = false

// The part of `WebSocketOptions` the native handshake reads, in the native layout.
export type WebSocketWire:
	// The `max_message_bytes` of the options.
	max_message_bytes: Int?
	// The `timeout` of the options.
	timeout: Duration?
	// The `tls` of the options.
	tls: TlsOptions
	// The `compression` of the options.
	compression: Bool
