import {buffered, headers, HttpRequest, HttpResponse, HttpServerOptions} from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"
import {sleep, nanoseconds} from "@std/time.ms"

fn handle(request: HttpRequest) HttpResponse:
    sleep(nanoseconds(600000000))
    return HttpResponse(200, headers(), "done".to_bytes())

export fn main() Int:
    if let acquired = network().serve(
        address: "127.0.0.1:0", handler: buffered(handle),
        options: HttpServerOptions(grace: nanoseconds(10000000000))
    ):
        let server = acquired
        stdout().write("{server.address()}\n").get()
        stdout().flush().get()

        let _ignored = server.wait()
        return 0

    return 1
