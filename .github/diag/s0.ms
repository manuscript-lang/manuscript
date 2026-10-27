from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds

def handle(request: HttpRequest) -> HttpResponse:
    return HttpResponse(200, headers(), "ok\n".to_bytes())

export def main() -> Int:
    let _a = stdout().write("start\n")
    let options = HttpServerOptions()
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle), options: options):
        let _b = stdout().write("served\n")
        with let server = acquired:
            let _c = stdout().write("in with\n")
            server.close()
            let _d = stdout().write("closed\n")
        let _e = stdout().write("after with\n")
        return 0
    let _f = stdout().write("serve failed\n")
    return 1
