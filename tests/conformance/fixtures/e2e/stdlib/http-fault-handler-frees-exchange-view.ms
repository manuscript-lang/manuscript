// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
import FetchOptions, fetch from "@std/net/fetch.ms"
import HttpExchange from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import milliseconds, sleep from "@std/time.ms"

fn faulting(var exchange: HttpExchange) Unit!:
    let xs: List[Int] = []
    let n = xs[5]
    if n > 5: return ok(unit)

    return ok(unit)

// The thunk that calls the handler keeps the exchange in a stack slot; a fault in the handler still releases it.
fn status() Int:
    let server = serve("127.0.0.1:0", faulting).get()
    let reply = fetch(
        "http://{server.address()}/", FetchOptions(timeout: milliseconds(2000))
    ).wait()
    return reply.get().head.status

export fn main() Int:
    print(status())
    let _ = sleep(milliseconds(300)).wait()
    return 0
