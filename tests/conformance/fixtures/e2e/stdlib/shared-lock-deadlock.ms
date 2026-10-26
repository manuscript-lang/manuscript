# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
from "@std/channels.ms" import Channel
from "@std/io.ms" import stdout
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds, sleep

def holder(box: Shared[Int], chan: Channel[Unit, Unit]) -> Int:
    var ch = chan.clone()
    with var g = lock(box):
        let never = ch.receive()
    return 0

def waiter(box: Shared[Int]) -> Int:
    with var g = lock(box):
        g.value = 1
    return 1

export def main() -> Int:
    let box = share(0)

    with let g = TaskGroup[Int, Unit, Unit]():
        g.spawn(lambda ch: holder(box, ch))
        sleep(nanoseconds(1000000))

        let w = g.spawn(lambda ch: waiter(box))
        stdout().write("waiting\n")
        w.result()

    return 0
