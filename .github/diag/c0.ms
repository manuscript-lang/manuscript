from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stderr
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds

def log(text: String) -> Unit:
    let _w = stderr().write(f"{text}\n")

def handle(request: HttpRequest) -> HttpResponse:
    log("handler")
    return HttpResponse(200, headers(), "ok\n".to_bytes())

export def main() -> Int:
    log("start")
    let options = HttpServerOptions()
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle), options: options):
        with let server = acquired:
            log("connect")
            if let conn = network().connect(server.address()):
                log("connected")
                let _sent = conn.write("GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                log("sent")
                if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                    log("read")
                conn.close()
            server.close()
        log("done")
        return 0
    return 1
