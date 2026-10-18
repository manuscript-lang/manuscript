import {expect_equal, expect_true, fail} from "@std/testing.ms"
import check_cancelled from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import Scheduler from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import WorkStatus from "@std/tasks.ms"

fn run() -> Result[Unit, Error]:
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
        number | try expect_equal(expected: 3)
        (flag) | try expect_true

    with empty = TaskGroup(0.seconds):
        let joined = try empty.join()
    return ok(unit)

fn scheduler_probe() -> Result[Unit, Error]:
    with service = Scheduler(limit: 1, drain: 2.seconds):
        let task = fn() -> Result[Unit, Error]:
            return ok(unit)
        let launch = service.start

        match launch(operation: task):
            ok(id):
                let completed = unit
            error(_):
                return fail(message: "Unexpected case")

        service.close()

        match launch(operation: task):
            ok(_):
                return fail(message: "Unexpected case")
            error(cause):
                try expect_equal(cause, StartError.Closed)

    return ok(unit)

test "joined work and snapshot captures":
    match run():
        ok(_):
            let completed = unit
        error(_):
            return fail(message: "Unexpected case")

    (try scheduler_probe())

fn standard_task() -> Result[Unit, Error]:
    with empty = TaskGroup():
        let joined = try empty.join()
    let checkpoint = check_cancelled

    with group = TaskGroup():
        let task = group.start(checkpoint)
        let completed = try task.join()
        completed | try expect_equal(expected: unit)

    return ok(unit)

test "standard functions can run concurrently":
    match standard_task():
        ok(_):
            let completed = unit
        error(_):
            return fail(message: "Unexpected case")
