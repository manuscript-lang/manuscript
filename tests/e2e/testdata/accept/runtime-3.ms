import panic from "@std/faults.ms"
import {ExecutionError, TaskGroup} from "@std/tasks.ms"

fn identity[T](value: T) T:
    return value

fn probe() Result[Unit, ExecutionError]:
    let first = fn() Result[Int, String]:
        return ok(3)
    let second = fn():
        return true

    with group = TaskGroup():
        let number_task = group.start(first) | identity
        let flag_task = group.start(second)
        let number = try number_task.join()
        let flag = try flag_task.join()
        if not (flag):
            return panic("check failed")
        if not (number.get(0) == 3):
            return panic("check failed")

        return ok(unit)

test "typed task helper":
    try probe()

fn describe(outcome: Result[Int, Int]) Result[Int, String]:
    if let value = outcome:
        return ok(value)

    return error("Error {outcome.err()}")

test "explicit error conversion":
    let failed: Result[Int, Int] = error(7)
    let expected: Result[Int, String] = error("Error 7")
    if not (describe(failed) == expected):
        return panic("check failed")

    let succeeded: Result[Int, Int] = ok(3)
    let unchanged: Result[Int, String] = ok(3)
    if not (describe(succeeded) == unchanged):
        return panic("check failed")
