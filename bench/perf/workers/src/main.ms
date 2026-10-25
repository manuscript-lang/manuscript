from "@std/channels.ms" import Channel, ChannelError
from "@std/io.ms" import stdout
from "@std/process.ms" import arguments
from "@std/workers.ms" import Worker, WorkerGroup, worker_channel

# Eight CPU-bound jobs spread over N workers. Usage: app <workers> [jobs] [n]
def fib(n: Int) -> Int:
    if n < 2:
        return n

    return fib(n - 1) + fib(n - 2)

def serve(var ch: Channel[Int, Int]) -> Result[Unit, ChannelError]:
    while True:
        if let n = try ch.receive():
            try ch.send(fib(n))
        else:
            return ok(())

    return ok(())

def compute() -> Unit:
    var ch = worker_channel[Int, Int]()
    let finished = serve(var ch)

def run(workers: Int, jobs: Int, n: Int) -> Result[Int, Error]:
    var total = 0

    with WorkerGroup[Int, Int]() as group:
        var handles: List[Worker[Int, Int]] = []
        for i in 0..workers:
            handles.append(try group.spawn(compute))
        for job in 0..jobs:
            try handles[job % workers].channel.send(n)
        for job in 0..jobs:
            if let value = try handles[job % workers].channel.receive():
                total += value
        for i in 0..workers:
            try handles[i].join()

    return ok(total)

export def main() -> Int:
    let args = arguments()
    let workers = args.get(0, default: "1").parse_int().get(1)
    let jobs = args.get(1, default: "8").parse_int().get(8)
    let n = args.get(2, default: "38").parse_int().get(38)

    if let total = run(workers, jobs, n):
        (
            stdout()
            .write(
                f"workers={workers} jobs={jobs} fib({n}) checksum={total}\n"
            )
            .get()
        )
        return 0

    return 1
