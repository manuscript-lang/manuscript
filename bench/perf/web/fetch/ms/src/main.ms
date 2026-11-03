import fetcher from "@std/net/fetch.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/process.ms"
import Promise, promise, wait_all from "@std/concurrency/promise.ms"
import nanoseconds, monotonic from "@std/os/time.ms"

fn worker(url: String, nanos: Int) Int:
    var f = fetcher().get()
    let started = monotonic()
    var n = 0

    while monotonic().difference(started).compare(nanoseconds(nanos)) < 0:
        if let r = f.fetch(url):
            n += r.body.length()
            n -= r.body.length() - 1
        else:
            return -1000000

    f.close().get(none)
    return n

// Runs `conns` fetching promises; the runtime spreads them over its threads.
export fn main() Int:
    let args = arguments()
    let url = args.get(0)
    let conns = args.get(1).parse_int().get()
    let secs = args.get(2).parse_int().get()
    var total = 0
    var running: List[Promise[Int]] = []
    for i in 0..conns:
        running.append(promise(fn: ok(worker(url.clone(), secs * 1000000000))))
    for r in wait_all(running).get():
        total += r

    let _ = stdout().write("req/s {total / secs}\n")
    return 0
