from "@std/io.ms" import stdout
from "@std/time.ms" import nanoseconds, sleep
from "@std/workers.ms" import WorkerGroup, worker_channel

def long() -> Unit:
    var ch = worker_channel[Int, Int]()
    for i in 0..600:
        sleep(nanoseconds(100000000))

export def main() -> Int:
    with let group = WorkerGroup[Int, Int]():
        var w = group.spawn(long).get()
        stdout().write("joining\n").get()
        stdout().flush().get()
        let outcome = w.wait()
        stdout().write(f"joined {outcome.is_ok()}\n").get()
    return 0
