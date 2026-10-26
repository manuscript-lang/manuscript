from "@std/collections.ms" import range
from "@std/fetch.ms" import fetcher, FetchOptions
from "@std/io.ms" import stdout
from "@std/process.ms" import arguments
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import clock, duration
from "@std/workers.ms" import Worker, WorkerGroup, worker_channel

def worker(url: String, nanos: Int) -> Int:
    var f = fetcher().get()
    let started = clock().now()
    var n = 0

    while clock().now().difference(started).compare(duration(nanos)) < 0:
        if let r = f.fetch(url):
            n += r.body.length()
            n -= r.body.length() - 1
        else:
            return -1000000

    f.close()
    return n

# One thread of a multi-threaded run: it receives "url connections seconds", runs that many fetching
# tasks, and sends back its request count.
def fetch_thread() -> Unit:
    var ch = worker_channel[Int, String]()

    if let job = ch.receive().get(none):
        let parts = job.split(" ")
        let conns = parts.get(1).parse_int().get(1)
        let nanos = parts.get(2).parse_int().get(1) * 1000000000
        var total = 0

        with let group = TaskGroup[Int]():
            for i in range(0, conns):
                let u = parts.get(0).clone()
                group.spawn(lambda ch: worker(u, nanos))

            for r in group.results().get():
                total += r

        ch.send(total)

# Spreads `conns` connections over `threads` worker threads and sums their requests.
def run_threads(url: String, conns: Int, secs: Int, threads: Int) -> Int:
    var total = 0

    with let group = WorkerGroup[String, Int]():
        var workers: List[Worker[String, Int]] = []

        for i in range(0, threads):
            var worker = group.spawn(fetch_thread).get(none)
            worker.channel.send(f"{url} {conns / threads} {secs}")
            workers.append(worker)

        for i in range(0, threads):
            if let n = workers[i].channel.receive().get(none):
                total += n

    return total

export def main() -> Int:
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
                    f"req/s {run_threads(url, conns, secs, threads) / secs}\n"
                )
                .get()
            )
            return 0

    with let group = TaskGroup[Int]():
        for i in range(0, conns):
            let u = url.clone()
            group.spawn(lambda ch: worker(u, secs * 1000000000))

        for r in group.results().get():
            total += r

    stdout().write(f"req/s {total / secs}\n")
    return 0
