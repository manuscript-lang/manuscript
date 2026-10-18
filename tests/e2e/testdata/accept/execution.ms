import panic from "@std/faults.ms"
import check_cancelled from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import Scheduler from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import WorkStatus from "@std/tasks.ms"

fn run() Result[Unit, ExecutionError]:
    var offset = 3
    let first = fn():
        return offset
    offset = 99
    let second = fn():
        return true

    with group = TaskGroup(1.seconds):
        let number_task = group.start(first)
        let flag_task = group.start(second)
        let joined = try group.join()
        let number = try number_task.join()
        let flag = try flag_task.join()
        if not (number == 3):
            return panic(message: "check failed")
        if not flag:
            return panic(message: "check failed")

    with empty = TaskGroup(0.seconds):
        let joined = try empty.join()
    return ok(unit)

fn scheduler_probe() Unit:
    with service = Scheduler(limit: 1, drain: 2.seconds):
        let task = fn() Result[Unit, Error]:
            return ok(unit)
        let launch = service.start
        if launch(operation: task).is_error():
            return panic(message: "Unexpected case")

        service.close()
        let closed = launch(operation: task)
        if closed.is_ok():
            return panic(message: "Unexpected case")
        if not (closed.unwrap_error() == StartError.Closed):
            return panic(message: "check failed")

test "joined work and snapshot captures":
    try run()
    scheduler_probe()

fn standard_task() Result[Unit, ExecutionError]:
    with empty = TaskGroup():
        let joined = try empty.join()
    let checkpoint = check_cancelled

    with group = TaskGroup():
        let completed = group.start(checkpoint) | try .join()
        if not (completed == unit):
            return panic(message: "check failed")

    return ok(unit)

test "standard functions can run concurrently":
    try standard_task()
