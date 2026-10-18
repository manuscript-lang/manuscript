import {headers, HttpRequest, HttpResponse} from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(
        status: 200,
        headers: headers(),
        body: "hello {request.path}".to_bytes()
    )

export fn main() Int:
    let serve = network().serve

    if let acquired = serve(
        address: "127.0.0.1:0",
        handler: handle,
        max_requests: 2,
        max_body_bytes: 1024,
        max_response_bytes: 1024,
        timeout: 2.seconds,
        grace: 0.seconds
    ):
        with server = acquired:
            if stdout().write(data: "{server.address()}\n".to_bytes()).is_error():
                return 1

            let _ignored = server.wait()
            return 0

    return 1
