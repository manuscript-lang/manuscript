import {buffered, headers, HttpRequest, HttpResponse} from "@std/http.ms"
import network from "@std/net.ms"

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), request.path.to_bytes())

export fn main() Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            return 0
    return 1
