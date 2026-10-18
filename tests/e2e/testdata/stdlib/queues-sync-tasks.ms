import {Queue, PriorityQueue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {Scheduler, StartError, WorkStatus, check_cancelled, yield_now, TaskGroup} from "@std/tasks.ms"
import {ListBuilder} from "@std/collections.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn compare(left: Int, right: Int) Int: left - right

fn operation() Result[Unit, Error]: ok(unit)

fn first() Int: 1

fn second() String: "two"

test "FIFO capacity empty reads draining and reuse":
    let queue = Queue[Int](2)
    if not queue.is_empty() or not queue.peek().is_none(): return panic("empty queue")
    if (not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)): return panic(
        "queue capacity"
    )
    if queue.peek() != some(1) or queue.length() != 2: return panic("queue peek")
    if queue.dequeue() != some(1) or queue.dequeue() != some(2): return panic("FIFO")
    if not queue.dequeue().is_none() or not queue.enqueue(4): return panic(
        "queue reuse"
    )

test "priority queue orders values and honors capacity":
    let queue = PriorityQueue(compare: compare, capacity: 3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    if queue.enqueue(0): return panic("priority capacity")
    if queue.peek() != some(1): return panic("priority peek")

    for expected in [1, 2, 3]:
        if queue.dequeue() != some(expected): return panic("priority order")
    if not queue.is_empty(): return panic("priority drain")

test "synchronized guards update and release for later acquisition":
    let state = Synchronized(1)

    with guard = state.lock():
        if guard.get() != 1: return panic("guard read")

        guard.set(2)

    with guard = state.lock():
        if guard.get() != 2: return panic("guard update or release")

test "scheduler delayed cancellation capacity and closed admission":
    let scheduler = Scheduler(limit: 1)
    let id = value(scheduler.after(duration: 60.seconds, operation: operation))
    if scheduler.status(id) != WorkStatus.Running: return panic("scheduled status")

    match scheduler.start(operation):
        ok(_): return panic("scheduler capacity ignored")
        error(cause):
            if cause != StartError.Full: return panic("scheduler capacity error")

    scheduler.cancel(id)
    scheduler.close()
    if scheduler.status(id) != WorkStatus.Cancelled: return panic(
        "joined cancel status"
    )

    scheduler.close()

    match scheduler.start(operation):
        ok(_): return panic("closed scheduler admitted work")
        error(cause):
            if cause != StartError.Closed: return panic("closed scheduler error")

test "task group heterogeneous results and cancellation checkpoints":
    check_cancelled()
    yield_now()

    with tasks = TaskGroup():
        let number_task = tasks.start(first)
        let text_task = tasks.start(second)
        let completed = value(tasks.join())
        let number = value(number_task.join())
        let text = value(text_task.join())
        if number != 1 or text != "two": return panic("task results changed")
