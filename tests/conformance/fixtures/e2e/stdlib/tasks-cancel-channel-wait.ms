# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
from "@std/channels.ms" import Channel
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import duration, sleep

# A task cancelled while parked in a channel send or receive must not drop the channel end twice:
# the receiver `var def` takes it out of the caller's slot, and the frames above own the same memory.
# Later allocations expose the corrupted heap.

def receiver(ch: Channel[Int, Int]) -> Int:
    var c = ch
    if let got = c.receive():
        return 1
    return 0

def sender(ch: Channel[Int, Int]) -> Int:
    var c = ch
    for i in 0..100:
        c.send(i)
    return 0

def cancel_receiver() -> Unit:
    with let group = TaskGroup[Int, Int, Int]():
        group.spawn(receiver)
        sleep(duration(1000000))

def cancel_sender() -> Unit:
    with let group = TaskGroup[Int, Int, Int]():
        group.spawn(sender)
        sleep(duration(1000000))

def timeout_receiver() -> Unit:
    with let group = TaskGroup[Int, Int, Int]():
        let task = group.spawn(receiver, timeout: some(duration(1000000)))
        task.result()

def churn() -> Int:
    var total = 0
    for round in 0..20:
        with let group = TaskGroup[String]():
            for i in 0..5:
                group.spawn(lambda ch: f"task {i}")
            total += group.results().get([]).length()
    return total

export def main() -> Int:
    var total = 0
    for round in 0..3:
        cancel_receiver()
        total += churn()
        cancel_sender()
        total += churn()
        timeout_receiver()
        total += churn()
    stdout().write(f"survived {total}\n").get()
    return 0
