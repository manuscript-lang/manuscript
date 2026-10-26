# conform: tags=stdlib-http,stdlib-net,tier-io
# conform: phase=run
# conform: timeout=30
# Closing a server lets a response in progress finish, and returns as soon as it has.
from "@std/http.ms" import headers, HttpRequest, HttpResponse, buffered
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/process.ms" import control
from "@std/time.ms" import nanoseconds, sleep

def handle(request: HttpRequest) -> HttpResponse:
    sleep(nanoseconds(300000000))
    return HttpResponse(200, headers(), "done\n".to_bytes())

export def main() -> Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            if let conn = network().connect(server.address()):
                let _sent = conn.write("GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

                # Let the handler start.
                sleep(nanoseconds(50000000))

                let start = control().monotonic_time()
                server.close()

                let close_ms = (control().monotonic_time() - start) / 1000000
                var text = ""

                while True:
                    if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                        if let data = chunk:
                            text = f"{text}{data.decode_utf8().get("?")}"
                            continue

                    break

                conn.close()

                let _status = stdout().write(
                    f"answered: {text.starts_with("HTTP/1.1 200 OK")}\n"
                )
                let _waited = stdout().write(
                    f"close waited for the handler: {close_ms >= 200}\n"
                )
                let _prompt = stdout().write(
                    f"close returned promptly: {close_ms < 2000}\n"
                )
                return 0

    return 1
