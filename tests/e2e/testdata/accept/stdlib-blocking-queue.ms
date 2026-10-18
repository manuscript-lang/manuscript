import BlockingQueue from "@std/queues.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn work(jobs: BlockingQueue[Int]) Int:
    var total = 0

    while true:
        if let value = jobs.take():
            total += value
        else:
            return total

fn total_of(task: Task[Int]) Int:
    if let total = task.join():
        return total

    return panic("worker failed")

test "bounded put and take block until the other side acts":
    let jobs = BlockingQueue[Int](2)

    with group = TaskGroup():
        let first = group.start(fn(): work(jobs))
        let second = group.start(fn(): work(jobs))
        for value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            if not jobs.put(value):
                return panic("put failed")
        jobs.close()
        let combined = total_of(first) + total_of(second)
        if not (combined == 55):
            return panic("lost or duplicated items")

test "close drains queued values then ends takers":
    let jobs = BlockingQueue[Int]()
    if not jobs.put(7):
        return panic("put failed")

    jobs.close()
    jobs.close()
    if not jobs.is_closed():
        return panic("close not observed")
    if jobs.put(8):
        return panic("put after close succeeded")
    if not (jobs.length() == 1):
        return panic("queued value lost")

    if let value = jobs.take():
        if not (value == 7):
            return panic("wrong value")
    else:
        return panic("queued value lost")

    if jobs.take().is_some():
        return panic("closed empty queue returned a value")

test "group close cancels a blocked taker":
    let jobs = BlockingQueue[Int](1)
    with group = TaskGroup():
        group.start(fn(): work(jobs))
