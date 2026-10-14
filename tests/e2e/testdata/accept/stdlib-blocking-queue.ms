import BlockingQueue from "@std/queues.ms"
import TaskGroup from "@std/tasks.ms"
import Task from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn work(jobs: BlockingQueue[Int]) -> Int:
    var total = 0

    while true:
        match jobs.take():
            some(value):
                total = total + value
            none:
                return total

    return total

fn total_of(task: Task[Int]) -> Int:
    match task.join():
        ok(total):
            return total
        error(_):
            return panic(message: "worker failed")

test "bounded put and take block until the other side acts":
    let jobs = BlockingQueue[Int](2)

    with group = TaskGroup():
        let first = group.start(fn(): work(jobs: jobs))
        let second = group.start(fn(): work(jobs: jobs))

        for value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            if not jobs.put(value):
                return panic(message: "put failed")

        jobs.close()
        let combined = total_of(task: first) + total_of(task: second)
        if not (combined == 55):
            return panic(message: "lost or duplicated items")

test "close drains queued values then ends takers":
    let jobs = BlockingQueue[Int]()
    if not jobs.put(7):
        return panic(message: "put failed")

    jobs.close()
    jobs.close()
    if not jobs.is_closed():
        return panic(message: "close not observed")
    if jobs.put(8):
        return panic(message: "put after close succeeded")
    if not (jobs.length() == 1):
        return panic(message: "queued value lost")

    match jobs.take():
        some(value):
            if not (value == 7):
                return panic(message: "wrong value")
        none:
            return panic(message: "queued value lost")

    if jobs.take().is_some():
        return panic(message: "closed empty queue returned a value")

test "group close cancels a blocked taker":
    let jobs = BlockingQueue[Int](1)

    with group = TaskGroup():
        group.start(fn(): work(jobs: jobs))
