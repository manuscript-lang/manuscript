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
    var _g = lock(box)
    let _never = ch.receive()
    _g.close()
    return 0

def waiter(box: Shared[Int]) -> Int:
    var g = lock(box)
    g.value = 1
    g.close()
    return 1

export def main() -> Int:
    let box = share(0)
    var g = TaskGroup[Int, Unit, Unit]()
    g.spawn(lambda ch: holder(box, ch))
    sleep(nanoseconds(1000000))

    let w = g.spawn(lambda ch: waiter(box))
    let _ = stdout().write("waiting\n")
    let _ = w.result()
    g.close()
    return 0
