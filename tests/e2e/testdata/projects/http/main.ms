import Process from "@std/cli.ms"
import Map from "@std/collections.ms"
import HttpRequest from "@std/http.ms"
import HttpResponse from "@std/http.ms"

fn handle(request: HttpRequest) -> HttpResponse:
    return HttpResponse(status: 200, headers: Map[String, String](), body: "hello {request.path}".to_bytes())

export fn main(process: Process) -> Int:
    let serve = process.network.serve
    match serve(
        address: "127.0.0.1:0",
        handler: handle,
        limit: 2,
        max_body_bytes: 1024,
        max_response_bytes: 1024,
        timeout: 2.seconds,
        grace: 0.seconds,
    ):
        error(_):
            return 1
        ok(acquired):
            with server = acquired:
                process.stdout.write(data: "{server.address()}\n".to_bytes())
                let outcome = server.wait()
                return 0
