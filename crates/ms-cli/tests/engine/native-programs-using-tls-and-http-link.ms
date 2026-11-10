import buffered, headers, HttpRequest, HttpResponse from "@std/net/http.ms"
import serve from "@std/net/net.ms"

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), request.path.to_bytes())

export fn main() Int:
    if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
        _server := acquired
        return 0

    return 1
