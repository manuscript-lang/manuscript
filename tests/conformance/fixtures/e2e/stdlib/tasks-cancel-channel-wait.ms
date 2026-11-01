# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

# A task cancelled while parked in a channel send or receive must not drop the channel end twice:
# the receiver `var def` takes it out of the caller's slot, and the frames above own the same memory.
# Later allocations expose the corrupted heap.

fn receiver(var ch: Channel[Int, Int]) Int:
    if let _got = ch.receive():
        return 1

    return 0

fn sender(var ch: Channel[Int, Int]) Int:
    for i in 0..100:
        let _ = ch.send(i)
    return 0

fn cancel_receiver() Unit:
    var group = TaskGroup[Int, Int, Int]()
    group.spawn(receiver)
    sleep(nanoseconds(1000000))

fn cancel_sender() Unit:
    var group = TaskGroup[Int, Int, Int]()
    group.spawn(sender)
    sleep(nanoseconds(1000000))

fn timeout_receiver() Unit:
    var group = TaskGroup[Int, Int, Int]()
    var task = group.spawn(receiver, timeout: nanoseconds(1000000))
    let _ = task.result()

fn churn() Int:
    var total = 0

    for round in 0..20:
        var group = TaskGroup[String]()
        for i in 0..5:
            group.spawn(fn var ch: "task {i}")
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
