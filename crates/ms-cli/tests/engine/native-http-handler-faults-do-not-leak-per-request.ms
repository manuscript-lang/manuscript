from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse
from "@std/net.ms" import network
from "@std/io.ms" import stdout

def handle(request: HttpRequest) -> HttpResponse:
    let xs: List[Int] = []
    let i = request.path.length()
    return HttpResponse(200, headers(), f"{xs[i]}".to_bytes())

export def main() -> Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        let server = acquired
        stdout().write(f"{server.address()}\n").get()
        stdout().flush().get()

        let _ignored = server.wait()
        return 0

    return 1
