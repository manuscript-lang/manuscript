import (
    buffered,
    headers,
    HttpRequest,
    HttpResponse,
    HttpServerOptions from "@std/net/http.ms",
    serve from "@std/net/net.ms",
    stdout from "@std/io/io.ms",
)

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), "hello {request.path}".to_bytes())

export fn main() Int:
    options := HttpServerOptions(
        max_requests: 2, max_body_bytes: 1024, max_response_bytes: 1024,
        timeout: 2.seconds(), grace: 0.seconds()
    )

    if acquired := serve(
        address: "127.0.0.1:0", handler: buffered(handle), options: options
    ):
        server := acquired
        if stdout().write("{server.address()}\n").is_error(): return 1

        _ignored := server.wait()
        return 0

    return 1
