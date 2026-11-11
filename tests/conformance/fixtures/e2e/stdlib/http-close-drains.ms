// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// Closing a server lets a response in progress finish; `wait` returns as soon as it has.
import headers, HttpRequest, HttpResponse, buffered from "@std/net/http.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import Bytes from "@std/bytes.ms"
import stdout, ReadStream from "@std/io/io.ms"
import Connection, connect, serve from "@std/net/net.ms"
import Duration, monotonic, nanoseconds, sleep from "@std/time.ms"

fn within(var input: ReadStream[Bytes], timeout: Duration) Bytes?!:
    return promise(fn: input.next()).with(options: PromiseOptions(timeout: timeout)).wait()

fn send(var conn: Connection, text: String) Unit!:
    conn.output.write(text.to_bytes())?
    return conn.output.flush()

fn handle(request: HttpRequest) HttpResponse:
    _ := sleep(nanoseconds(300000000)).wait()
    return HttpResponse(200, headers(), "done\n".to_bytes())

export fn main() Int:
    if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
        var server = acquired

        if var conn = connect(server.address()).wait():
            _sent := send(var conn, "GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

            // Let the handler start.
            _ := sleep(nanoseconds(50000000)).wait()
            start := monotonic()
            server.close().get(none)
            server.wait().get(none)

            close_ms := monotonic().difference(start).to_milliseconds()
            var text = ""

            while true:
                if chunk := within(var conn.input, nanoseconds(5000000000)):
                    if data := chunk:
                        text = "{text}{data.decode_utf8().get("?")}"
                        continue

                break

            conn.close().get(none)

            _status := stdout().write(
                "answered: {text.starts_with("HTTP/1.1 200 OK")}\n"
            )
            _waited := stdout().write(
                "close waited for the handler: {close_ms >= 200}\n"
            )
            _prompt := stdout().write("close returned promptly: {close_ms < 2000}\n")
            return 0

    return 1
