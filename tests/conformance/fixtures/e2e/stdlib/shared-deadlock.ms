# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn wait_forever(var value: Int, chan: Channel[Unit, Unit]) Unit:
    var ch = chan.clone()
    let _never = ch.receive()

fn holder(var box: Shared[Int], chan: Channel[Unit, Unit]) Int:
    wait_forever(var box, chan)
    return 0

fn waiter(var box: Shared[Int]) Int:
    box = 1
    return 1

export fn main() Int:
    var box = Shared(0)
    var g = TaskGroup[Int, Unit, Unit]()
    var first = box
    g.spawn(fn ch: holder(var first, ch))
    sleep(nanoseconds(1000000))

    var second = box
    let w = g.spawn(fn ch: waiter(var second))
    let _ = stdout().write("waiting\n")
    let _ = w.result()
    g.close().get(none)
    return 0
