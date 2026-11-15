import buffered, headers, HttpRequest, HttpResponse from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import stdout from "@std/io/io.ms"

fn handle(request: HttpRequest) HttpResponse:
    xs: List[Int] := []
    i := request.path.length()
    return HttpResponse(200, headers(), f"{xs[i]}".to_bytes())

export fn main() Int:
    if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
        server := acquired
        print(f"{server.address()}")

        _flushed := stdout().flush()
        _ignored := server.wait()
        return 0

    return 1
