# conform: tags=stdlib-http,stdlib-net,tier-io
# conform: phase=run
# conform: timeout=30
# A request that arrives on a connection while its handler is parked is served as soon as
# the handler's response is sent, not after a timeout.
import {headers, HttpRequest, HttpResponse, buffered} from "@std/http.ms"
import stdout from "@std/io.ms"
import network from "@std/net.ms"
import control from "@std/process.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn handle(request: HttpRequest) HttpResponse:
    if request.path == "/slow":
        sleep(nanoseconds(200000000))
    return HttpResponse(200, headers(), "ok {request.path}\n".to_bytes())

fn exchange(address: String) String:
    if var conn = network().connect(address):
        let _first = conn.write("GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

        # The slow handler is parked by now; the second request arrives while it waits.
        sleep(nanoseconds(50000000))

        let _second = conn.write(
            "GET /fast HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
        )
        var text = ""

        while true:
            if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                if let data = chunk:
                    text = "{text}{data.decode_utf8().get("?")}"
                    continue

            break

        conn.close()
        return text

    return "connect failed"

export fn main() Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        var server = acquired
        let start = control().monotonic_time()
        let text = exchange(server.address())
        let elapsed_ms = (control().monotonic_time() - start) / 1000000
        let _count = stdout().write(
            "responses: {text.split("HTTP/1.1 200 OK").length() - 1}\n"
        )
        let _order = stdout().write(
            "slow first: {text.index_of("ok /slow").get(-1) < text.index_of("ok /fast").get(-1)}\n"
        )
        let _prompt = stdout().write("prompt: {elapsed_ms < 2000}\n")
        server.close()
        return 0

    return 1
