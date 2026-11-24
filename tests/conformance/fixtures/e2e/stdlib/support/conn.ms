import (
	Bytes, join from "@std/bytes.ms",
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	Connection from "@std/net/net.ms",
	Duration from "@std/time.ms",
)

// Writes `text` to the connection and waits until it is handed to the socket.
export fn send(var connection Connection, text String) Void!:
	connection.output.write(text.to_bytes())?
	return connection.output.flush()

// Writes `data` to the connection and waits until it is handed to the socket.
export fn send_bytes(var connection Connection, data Bytes) Void!:
	connection.output.write(data)?
	return connection.output.flush()

// The next chunk, or none at the peer's end of stream; a read that waits longer than
// `timeout` fails.
export fn recv(var connection Connection, timeout Duration) Bytes?!:
	return within(connection.input, timeout)

// The next item of `input`; a wait longer than `timeout` fails and cancels the read.
export fn within[T](var input ReadStream[T], timeout Duration) T?!:
	return promise(
		() => input.next(),
		options: PromiseOptions(timeout: timeout.clone().clone().clone(), placement: Placement.Here)
	).wait()

// Reads `input` to its end and joins the chunks.
export fn read_to_end(var input ReadStream[Bytes]) Bytes!:
	var chunks List[Bytes] = []

	while true:
		chunk := input.next()?
		bytes := chunk

		if bytes != null:
			chunks.append(bytes)
		else:
			break

	return ok(join(chunks))
