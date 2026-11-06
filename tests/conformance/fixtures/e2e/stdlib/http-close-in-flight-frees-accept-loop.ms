// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
import FetchOptions, fetch from "@std/net/fetch.ms"
import HttpRequest, HttpResponse, headers, buffered from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import milliseconds, sleep from "@std/time.ms"

fn route(request: HttpRequest) HttpResponse:
    let _ = sleep(milliseconds(2000)).wait()
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

// The client gives up while the handler sleeps, and dropping the server cancels the accept loop, whose cleanup frees what it owns.
fn run() Bool:
    let server = serve("127.0.0.1:0", buffered(route)).get()
    let slow = fetch(
        "http://{server.address()}/slow", FetchOptions(timeout: milliseconds(200))
    ).wait()
    return slow.is_error()

export fn main() Int:
    print(if run(): "timed out" else: "answered")
    let _ = sleep(milliseconds(500)).wait()
    return 0
