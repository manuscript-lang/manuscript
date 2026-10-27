from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stdout, stderr
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds, sleep

def handle(request: HttpRequest) -> HttpResponse:
    sleep(nanoseconds(300000000))
    return HttpResponse(200, headers(), "done\n".to_bytes())

export def main() -> Int:
    let _z = 0
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            let _y = 0
            if let conn = network().connect(server.address()):
                let _sent = conn.write("GET /slow HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                sleep(nanoseconds(50000000))
                var text = ""
                while True:
                    if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                        if let data = chunk:
                            text = f"{text}{data.decode_utf8().get("?")}"
                            continue

                    break

                conn.close()
                server.close()
                let _o = stdout().write(f"OK {text.starts_with("HTTP/1.1 200 OK")}\n")
                return 0

    return 1
