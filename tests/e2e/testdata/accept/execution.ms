import panic from "@std/faults.ms"

import check_cancelled from "@std/tasks.ms"
import Result from "@std/result.ms"
import Optional from "@std/optional.ms"
import parallel from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import Background from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import WorkStatus from "@std/tasks.ms"

fn run() -> Result[Unit, ExecutionError]:
    var offset = 3
    let first = fn() -> Int:
        return offset
    offset = 99
    let second = fn() -> Bool:
        return true
    let [number, flag] = try parallel(timeout: 1.seconds, tasks: [first, second])
    if not (number == 3):
        return panic(message: "check failed")
    if not (flag):
        return panic(message: "check failed")
    let [] = try parallel(tasks: [], timeout: 0.seconds)
    return ok(value: unit)

fn background_probe() -> Unit:
    with service = Background(limit: 1, drain: 2.seconds):
        let task = fn() -> Result[Unit, String]:
            return ok(value: unit)
        let launch = service.start
        match launch(operation: task):
            ok(id):
                let completed = unit
            error(_):
                return panic(message: "Unexpected case")
        service.close()
        match launch(operation: task):
            ok(_):
                return panic(message: "Unexpected case")
            error(cause):
                if not (cause == StartError.Closed):
                    return panic(message: "check failed")

test "joined work and snapshot captures":
    match run():
        ok(_):
            let completed = unit
        error(_):
            return panic(message: "Unexpected case")
    background_probe()


fn standard_task() -> Result[Unit, ExecutionError]:
    let [] = try parallel(tasks: [])
    let checkpoint = check_cancelled
    let [completed] = try parallel(tasks: [checkpoint])
    if not (completed == unit):
        return panic(message: "check failed")
    return ok(value: unit)

test "standard functions can run concurrently":
    match standard_task():
        ok(_):
            let completed = unit
        error(_):
            return panic(message: "Unexpected case")
