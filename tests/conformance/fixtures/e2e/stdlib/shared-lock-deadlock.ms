# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/channels.ms"
import stdout from "@std/io.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn holder(box: Lock[Int], chan: Channel[Unit, Unit]) Int:
    var ch = chan.clone()
    var _g = box.lock()
    let _never = ch.receive()
    _g.close()
    return 0

fn waiter(box: Lock[Int]) Int:
    var g = box.lock()
    g.value = 1
    g.close()
    return 1

export fn main() Int:
    let box = new_lock(0)
    var g = TaskGroup[Int, Unit, Unit]()
    g.spawn(fn ch: holder(box, ch))
    sleep(nanoseconds(1000000))

    let w = g.spawn(fn ch: waiter(box))
    let _ = stdout().write("waiting\n")
    let _ = w.result()
    g.close()
    return 0
