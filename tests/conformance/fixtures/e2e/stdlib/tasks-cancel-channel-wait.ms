# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/channels.ms"
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"
import {nanoseconds, sleep} from "@std/time.ms"

# A task cancelled while parked in a channel send or receive must not drop the channel end twice:
# the receiver `var def` takes it out of the caller's slot, and the frames above own the same memory.
# Later allocations expose the corrupted heap.

fn receiver(ch: Channel[Int, Int]) Int:
    var c = ch
    if let _got = c.receive():
        return 1

    return 0

fn sender(ch: Channel[Int, Int]) Int:
    var c = ch
    for i in 0..100:
        let _ = c.send(i)
    return 0

fn cancel_receiver() Unit:
    with let group = TaskGroup[Int, Int, Int]():
        group.spawn(receiver)
        sleep(nanoseconds(1000000))

fn cancel_sender() Unit:
    with let group = TaskGroup[Int, Int, Int]():
        group.spawn(sender)
        sleep(nanoseconds(1000000))

fn timeout_receiver() Unit:
    with let group = TaskGroup[Int, Int, Int]():
        let task = group.spawn(receiver, timeout: some(nanoseconds(1000000)))
        let _ = task.result()

fn churn() Int:
    var total = 0

    for round in 0..20:
        with let group = TaskGroup[String]():
            for i in 0..5:
                group.spawn(fn ch: "task {i}")
            total += group.results().get([]).length()

    return total

export fn main() Int:
    var total = 0

    for round in 0..3:
        cancel_receiver()
        total += churn()
        cancel_sender()
        total += churn()
        timeout_receiver()
        total += churn()

    stdout().write("survived {total}\n").get()
    return 0
