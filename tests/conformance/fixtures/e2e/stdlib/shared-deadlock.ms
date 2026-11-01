# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn wait_forever(var value: Int, var chan: Channel[Unit, Unit]) Unit:
    var ch = chan.clone()
    let _never = ch.receive()

fn holder(var box: Shared[Int], var chan: Channel[Unit, Unit]) Int:
    wait_forever(var box, var chan)
    return 0

fn waiter(var box: Shared[Int]) Int:
    box = 1
    return 1

export fn main() Int:
    var box = Shared(0)
    var g = TaskGroup[Int, Unit, Unit]()
    var first = box
    g.spawn(fn var ch: holder(var first, var ch))
    sleep(nanoseconds(1000000))

    var second = box
    var w = g.spawn(fn var ch: waiter(var second))
    let _ = stdout().write("waiting\n")
    let _ = w.result()
    g.close().get(none)
    return 0
