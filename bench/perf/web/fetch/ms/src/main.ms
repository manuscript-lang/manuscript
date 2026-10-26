from "@std/collections.ms" import range
from "@std/fetch.ms" import fetcher, FetchOptions
from "@std/io.ms" import stdout
from "@std/process.ms" import arguments
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import clock, duration

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

export def main() -> Int:
    let args = arguments()
    let url = args.get(0)
    let conns = args.get(1).parse_int().get()
    let secs = args.get(2).parse_int().get()
    var total = 0

    with let group = TaskGroup[Int]():
        for i in range(0, conns):
            let u = url.clone()
            group.spawn(lambda ch: worker(u, secs * 1000000000))

        for r in group.results().get():
            total += r

    stdout().write(f"req/s {total / secs}\n")
    return 0
