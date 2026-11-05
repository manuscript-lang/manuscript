// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
import headers, HttpRequest, HttpResponse, buffered, HttpServerOptions from "@std/net/http.ms"
import serve from "@std/net/net.ms"

fn ok_route(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

// A serve call that fails in the runtime, here on a zero request timeout, still releases the handler it was given.
export fn main() Int:
    let started = serve("127.0.0.1:0", buffered(ok_route), HttpServerOptions(timeout: 0.seconds()))
    print(started.is_error())
    return 0
