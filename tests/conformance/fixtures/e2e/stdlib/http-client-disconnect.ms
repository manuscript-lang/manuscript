# conform: tags=stdlib-http,stdlib-net,tier-io
# conform: phase=run
# conform: timeout=30
# A handler whose client went away is cancelled: its wait ends and its cleanup runs with
# tasks.cancelled() true.
import Closeable from "@std/core.ms"
import buffered, headers, HttpRequest, HttpResponse from "@std/http.ms"
import stdout from "@std/io.ms"
import network from "@std/net.ms"
import cancelled from "@std/tasks.ms"
import nanoseconds, sleep from "@std/time.ms"

type Reporter:
    name: String

impl Closeable for Reporter:
    var fn close() Unit:
        let _line = stdout().write(
            "{self.name} cleanup sees cancelled: {cancelled()}\n"
        )

fn handle(request: HttpRequest) HttpResponse:
    var _reporter = Reporter("handler")
    sleep(nanoseconds(30000000000))
    _reporter.close()
    return HttpResponse(200, headers(), "late\n".to_bytes())

export fn main() Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        var server = acquired

        if var conn = network().connect(server.address()):
            let _sent = conn.write("GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

            # Let the handler start, then leave without waiting for the response.
            sleep(nanoseconds(100000000))
            conn.close()
            sleep(nanoseconds(500000000))

            let _done = stdout().write("done\n")
            server.close()
            return 0

    return 1
