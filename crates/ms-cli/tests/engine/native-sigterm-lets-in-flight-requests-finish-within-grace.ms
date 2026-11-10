import (
    buffered,
    headers,
    HttpRequest,
    HttpResponse,
    HttpServerOptions
) from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/time.ms"

fn handle(request: HttpRequest) HttpResponse:
    print("started")

    _flushed := stdout().flush()
    _ := sleep(nanoseconds(600000000)).wait()
    return HttpResponse(200, headers(), "done".to_bytes())

export fn main() Int:
    if acquired := serve(
        address: "127.0.0.1:0", handler: buffered(handle),
        options: HttpServerOptions(grace: nanoseconds(10000000000))
    ):
        server := acquired
        print("{server.address()}")

        _flushed := stdout().flush()
        _ignored := server.wait()
        return 0

    return 1
