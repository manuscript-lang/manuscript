# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import Shared, share from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn holder(box: Shared[Int], chan: Channel[Unit, Unit]) Int:
    var ch = chan.clone()
    var _g = box.lock()
    let _never = ch.receive()
    _g.close().get(none)
    return 0

fn waiter(box: Shared[Int]) Int:
    var g = box.lock()
    g.value = 1
    g.close().get(none)
    return 1

export fn main() Int:
    let box = share(0)
    var g = TaskGroup[Int, Unit, Unit]()
    g.spawn(fn ch: holder(box, ch))
    sleep(nanoseconds(1000000))

    let w = g.spawn(fn ch: waiter(box))
    let _ = stdout().write("waiting\n")
    let _ = w.result()
    g.close().get(none)
    return 0
