import {buffered, headers, HttpRequest, HttpResponse, HttpServerOptions} from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), "hello {request.path}".to_bytes())

export fn main() Int:
    let serve = network().serve
    let options = HttpServerOptions(
        max_requests: 2, max_body_bytes: 1024, max_response_bytes: 1024,
        timeout: 2.seconds, grace: 0.seconds
    )

    if let acquired = serve(
        address: "127.0.0.1:0", handler: buffered(handle), options: options
    ):
        with let server = acquired:
            if stdout().write("{server.address()}\n").is_error():
                return 1

            let _ignored = server.wait()
            return 0

    return 1
