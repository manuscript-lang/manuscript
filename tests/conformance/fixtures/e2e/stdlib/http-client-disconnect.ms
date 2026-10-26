# conform: tags=stdlib-http,stdlib-net,tier-io
# conform: phase=run
# conform: timeout=30
# A handler whose client went away is cancelled: its wait ends and its cleanup runs with
# tasks.cancelled() true.
from "@std/core.ms" import Closeable
from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/tasks.ms" import cancelled
from "@std/time.ms" import duration, sleep

type Reporter:
    name: String

impl Closeable for Reporter:
    var def close() -> Unit:
        let _line = stdout().write(
            f"{self.name} cleanup sees cancelled: {cancelled()}\n"
        )

def handle(request: HttpRequest) -> HttpResponse:
    with let reporter = Reporter("handler"):
        sleep(duration(30000000000))
    return HttpResponse(200, headers(), "late\n".to_bytes())

export def main() -> Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            if let conn = network().connect(server.address()):
                let _sent = conn.write("GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

                # Let the handler start, then leave without waiting for the response.
                sleep(duration(100000000))
                conn.close()
                sleep(duration(500000000))

                let _done = stdout().write("done\n")
                server.close()
                return 0

    return 1
