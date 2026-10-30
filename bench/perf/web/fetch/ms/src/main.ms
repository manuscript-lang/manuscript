import fetcher, FetchOptions from "@std/fetch.ms"
import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import TaskGroup from "@std/tasks.ms"
import clock, nanoseconds from "@std/time.ms"
import Worker, WorkerGroup, worker_channel from "@std/workers.ms"

fn worker(url: String, nanos: Int) Int:
    var f = fetcher().get()
    let started = clock().now()
    var n = 0

    while clock().now().difference(started).compare(nanoseconds(nanos)) < 0:
        if let r = f.fetch(url):
            n += r.body.length()
            n -= r.body.length() - 1
        else:
            return -1000000

    f.close()
    return n

# One thread of a multi-threaded run: it receives "url connections seconds", runs that many fetching
# tasks, and sends back its request count.
fn fetch_thread() Unit:
    var ch = worker_channel[Int, String]()

    if let job = ch.receive().get(none):
        let parts = job.split(" ")
        let conns = parts.get(1).parse_int().get(1)
        let nanos = parts.get(2).parse_int().get(1) * 1000000000
        var total = 0
        var group = TaskGroup[Int]()

        for i in 0..conns:
            let u = parts.get(0).clone()
            group.spawn(fn task: worker(u, nanos))

        for r in group.results().get():
            total += r
        group.close()

        let _ = ch.send(total)

# Spreads `conns` connections over `threads` worker threads and sums their requests.
fn run_threads(url: String, conns: Int, secs: Int, threads: Int) Int:
    var total = 0
    var group = WorkerGroup[String, Int]()
    var workers: List[Worker[String, Int]] = []

    for i in 0..threads:
        var worker = group.spawn(fetch_thread).get(none)
        let _ = worker.channel.send("{url} {conns / threads} {secs}")
        workers.append(worker)

    for i in 0..threads:
        if let n = workers[i].channel.receive().get(none):
            total += n
    group.close()
    return total

export fn main() Int:
    let args = arguments()
    let url = args.get(0)
    let conns = args.get(1).parse_int().get()
    let secs = args.get(2).parse_int().get()
    var total = 0

    if args.length() > 3:
        let threads = args.get(3).parse_int().get(1)

        if threads > 1:
            (
                stdout()
                .write(
                    "req/s {run_threads(url, conns, secs, threads) / secs}\n"
                )
                .get()
            )
            return 0

    var group = TaskGroup[Int]()

    for i in 0..conns:
        let u = url.clone()
        group.spawn(fn ch: worker(u, secs * 1000000000))

    for r in group.results().get():
        total += r
    group.close()

    let _ = stdout().write("req/s {total / secs}\n")
    return 0
