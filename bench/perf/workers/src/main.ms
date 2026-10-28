import {Channel, ChannelError} from "@std/channels.ms"
import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import {Worker, WorkerGroup, worker_channel} from "@std/workers.ms"

# Eight CPU-bound jobs spread over N workers. Usage: app <workers> [jobs] [n]
fn fib(n: Int) Int:
    if n < 2:
        return n

    return fib(n - 1) + fib(n - 2)

fn serve(var ch: Channel[Int, Int]) Result[Unit, ChannelError]:
    while true:
        if let n = try ch.receive():
            try ch.send(fib(n))
        else:
            return ok(unit)

    return ok(unit)

fn compute() Unit:
    var ch = worker_channel[Int, Int]()
    let _finished = serve(var ch)

fn run(workers: Int, jobs: Int, n: Int) Result[Int, Error]:
    var total = 0

    with let group = WorkerGroup[Int, Int]():
        var handles: List[Worker[Int, Int]] = []
        for i in 0..workers:
            handles.append(try group.spawn(compute))
        for job in 0..jobs:
            try handles[job % workers].channel.send(n)
        for job in 0..jobs:
            if let value = try handles[job % workers].channel.receive():
                total += value
        for i in 0..workers:
            try handles[i].wait()

    return ok(total)

export fn main() Int:
    let args = arguments()
    let workers = args.get(0, default: "1").parse_int().get(1)
    let jobs = args.get(1, default: "8").parse_int().get(8)
    let n = args.get(2, default: "38").parse_int().get(38)

    if let total = run(workers, jobs, n):
        (
            stdout()
            .write(
                "workers={workers} jobs={jobs} fib({n}) checksum={total}\n"
            )
            .get()
        )
        return 0

    return 1
