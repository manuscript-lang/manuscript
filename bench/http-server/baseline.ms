# Build only with archived commit 0385da26a0bfcd3c891f332ba6883ed7c8372038.
# Its positional serve options intentionally differ from the current API.
from "@std/net.ms" import network
from "@std/http.ms" import HttpRequest, HttpResponse, headers
from "@std/process.ms" import arguments
from "@std/time.ms" import sleep

def handle(request: HttpRequest) -> HttpResponse:
    if request.path == "/cpu":
        var value = 17
        var index = 0

        while index < 100000:
            value = (value * 31 + index) % 1000000007
            index += 1

        return HttpResponse(200, headers(), f"0:{value}".to_bytes())

    if request.path == "/slow": sleep(20.milliseconds)
    return HttpResponse(200, headers(), "0".to_bytes())

export def main() -> Int:
    let address = arguments().get(2, "127.0.0.1:19746").clone()
    with (
        network()
        .serve(
            address, handle, max_requests: 64, max_body_bytes: 1048576,
            max_response_bytes: 1048576, timeout: 2.seconds, grace: 2.seconds
        )
        .get()
    ) as server:
        server.wait().get()
    return 0
