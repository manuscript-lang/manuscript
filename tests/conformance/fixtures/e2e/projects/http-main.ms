# conform: tags=control-flow,diagnostics,interpolation,modules,stdlib-http,stdlib-io,stdlib-net,tier-io,with-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/http/main.ms
from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/net.ms" import network
from "@std/io.ms" import stdout

def handle(request: HttpRequest) -> HttpResponse:
    return HttpResponse(200, headers(), f"hello {request.path}".to_bytes())

export def main() -> Int:
    let serve = network().serve
    let options = HttpServerOptions(
        max_requests: 2, max_body_bytes: 1024, max_response_bytes: 1024,
        timeout: 2.seconds, grace: 0.seconds
    )

    if let acquired = serve(
        address: "127.0.0.1:0", handler: buffered(handle), options: options
    ):
        let server = acquired
        if stdout().write(f"{server.address()}\n").is_error():
            return 1

        let _ignored = server.wait()
        return 0

    return 1
