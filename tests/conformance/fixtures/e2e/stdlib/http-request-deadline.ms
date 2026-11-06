// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A handler that is still waiting when the server's request timeout passes is cancelled and the
// request is answered 504, with or without a grace period; the server keeps serving afterwards.
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import Bytes from "@std/bytes.ms"
import (
    buffered,
    headers,
    HttpRequest,
    HttpResponse,
    HttpServerOptions
) from "@std/net/http.ms"
import stdout, ReadStream from "@std/io/io.ms"
import Connection, connect, serve from "@std/net/net.ms"
import monotonic_time from "@std/os/system.ms"
import Duration, nanoseconds, sleep from "@std/time.ms"

fn within(var input: ReadStream[Bytes], timeout: Duration) Bytes?!:
    return promise(fn: input.next()).with(options: PromiseOptions(timeout: timeout)).wait()

fn send(var conn: Connection, text: String) Unit!:
    try conn.output.write(text.to_bytes())
    return conn.output.flush()

fn handle(request: HttpRequest) HttpResponse:
    if request.path == "/slow":
        let _ = sleep(nanoseconds(3000000000)).wait()
    return HttpResponse(200, headers(), "ok {request.path}\n".to_bytes())

fn fetch(address: String, path: String) String:
    if var conn = connect(address).wait():
        let _sent = send(
            var conn, "GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
        )
        var text = ""

        while true:
            if let chunk = within(var conn.input, nanoseconds(5000000000)):
                if let data = chunk:
                    text = "{text}{data.decode_utf8().get("?")}"
                    continue

            break

        conn.close().get(none)
        return text

    return "connect failed"

fn run(label: String, grace_ms: Int) Bool:
    let options = HttpServerOptions(
        timeout: nanoseconds(200000000), grace: nanoseconds(grace_ms * 1000000)
    )

    if let acquired = serve(
        address: "127.0.0.1:0", handler: buffered(handle), options: options
    ):
        var server = acquired
        let start = monotonic_time()
        let slow = fetch(server.address(), "/slow")
        let elapsed_ms = (monotonic_time() - start) / 1000000
        let fast = fetch(server.address(), "/fast")
        let _slow = stdout().write(
            "{label} slow: {slow.starts_with("HTTP/1.1 504")} prompt: {elapsed_ms < 2000}\n"
        )
        let _fast = stdout().write(
            "{label} fast: {fast.starts_with("HTTP/1.1 200 OK")}\n"
        )
        server.close().get(none)
        return true

    return false

export fn main() Int:
    if run("no grace", 0):
        if run("grace", 500):
            return 0
    return 1
