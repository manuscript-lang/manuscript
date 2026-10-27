from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse
from "@std/net.ms" import network

def handle(request: HttpRequest) -> HttpResponse:
    return HttpResponse(200, headers(), request.path.to_bytes())

export def main() -> Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            return 0
    return 1
