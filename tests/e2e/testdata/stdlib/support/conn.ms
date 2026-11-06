import Bytes, join from "@std/bytes.ms"
import PromiseOptions from "@std/concurrency/promise.ms"
import Connection from "@std/net/net.ms"
import Duration from "@std/time.ms"
import ReadStream from "@std/io/io.ms"

// Writes `text` to the connection and waits until it is handed to the socket.
export fn send(var connection: Connection, text: String) Unit!:
    try connection.output.write(text.to_bytes())
    return connection.output.flush().wait()

// Writes `data` to the connection and waits until it is handed to the socket.
export fn send_bytes(var connection: Connection, data: Bytes) Unit!:
    try connection.output.write(data)
    return connection.output.flush().wait()

// The next chunk, or none at the peer's end of stream; a read that waits longer than `timeout` fails.
export fn recv(var connection: Connection, timeout: Duration) Bytes?!:
    return connection.input.read().with(
        options: PromiseOptions(timeout: timeout)
    ).wait()

// Reads `input` to its end and joins the chunks.
export fn read_to_end(var input: ReadStream[Bytes]) Bytes!:
    var chunks: List[Bytes] = []

    while true:
        let chunk = try input.read().wait()

        if let bytes = chunk:
            chunks.append(bytes)
        else:
            break

    return ok(join(chunks))
