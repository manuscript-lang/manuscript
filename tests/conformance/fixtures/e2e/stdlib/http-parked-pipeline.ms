// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A request that arrives on a connection while its handler is parked is served as soon as
// the handler's response is sent, not after a timeout.
import headers, HttpRequest, HttpResponse, buffered from "@std/net/http.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import Bytes from "@std/bytes.ms"
import stdout, ReadStream from "@std/io/io.ms"
import Connection, connect, serve from "@std/net/net.ms"
import Duration, monotonic, nanoseconds, sleep from "@std/time.ms"

fn within(var input: ReadStream[Bytes], timeout: Duration) Bytes?!:
    return promise(fn: input.next()).with(options: PromiseOptions(timeout: timeout)).wait()

fn send(var conn: Connection, text: String) Unit!:
    try conn.output.write(text.to_bytes())
    return conn.output.flush()

fn handle(request: HttpRequest) HttpResponse:
    if request.path == "/slow":
        _ := sleep(nanoseconds(200000000)).wait()
    return HttpResponse(200, headers(), "ok {request.path}\n".to_bytes())

fn exchange(address: String) String:
    if var conn = connect(address).wait():
        _first := send(var conn, "GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

        // The slow handler is parked by now; the second request arrives while it waits.
        _ := sleep(nanoseconds(50000000)).wait()
        _second := send(
            var conn, "GET /fast HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
        )
        var text = ""

        while true:
            if chunk := within(var conn.input, nanoseconds(5000000000)):
                if data := chunk:
                    text = "{text}{data.decode_utf8().get("?")}"
                    continue

            break

        conn.close().get(none)
        return text

    return "connect failed"

export fn main() Int:
    if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
        var server = acquired
        start := monotonic()
        text := exchange(server.address())
        elapsed_ms := monotonic().difference(start).to_milliseconds()
        _count := stdout().write(
            "responses: {text.split("HTTP/1.1 200 OK").length() - 1}\n"
        )
        _order := stdout().write(
            "slow first: {text.index_of("ok /slow").get(-1) < text.index_of("ok /fast").get(-1)}\n"
        )
        _prompt := stdout().write("prompt: {elapsed_ms < 2000}\n")
        server.close().get(none)
        return 0

    return 1
