import stdout from "@std/io/io.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import WorkerGroup, worker_channel from "@std/concurrency/workers.ms"

fn long() Unit:
    var _ch = worker_channel[Int, Int]()
    for i in 0..600:
        sleep(nanoseconds(100000000))

export fn main() Int:
    var group = WorkerGroup[Int, Int]()
    var w = group.spawn(long).get()
    stdout().write("joining\n").get()
    stdout().flush().get()

    let outcome = w.wait()
    stdout().write("joined {outcome.is_ok()}\n").get()
    group.close().get(none)
    return 0
