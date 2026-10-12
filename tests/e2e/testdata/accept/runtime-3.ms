import panic from "@std/faults.ms"

import Result from "@std/result.ms"
import ExecutionError from "@std/tasks.ms"
import parallel from "@std/tasks.ms"

fn identity[T](value: T) -> T:
    return value

fn probe() -> Result[Unit, ExecutionError]:
    let first = fn() -> Result[Int, String]:
        return ok(value: 3)
    let second = fn() -> Bool:
        return true
    let packed = try parallel(tasks: [first, second])
    let copied = identity(value: packed)
    let [number, flag] = copied
    if not (flag):
        return panic(message: "check failed")
    match number:
        ok(value):
            if not (value == 3):
                return panic(message: "check failed")
        error(_):
            return panic(message: "Unexpected case")
    return ok(value: unit)

test "pack helper":
    match probe():
        ok(_):
            let completed = unit
        error(_):
            return panic(message: "Unexpected case")

fn describe(outcome: Result[Int, Int]) -> Result[Int, String]:
    match outcome:
        ok(value):
            return ok(value: value)
        error(cause):
            return error(cause: "Error {cause}")

test "explicit error conversion":
    let failed: Result[Int, Int] = error(cause: 7)
    let expected: Result[Int, String] = error(cause: "Error 7")
    if not (describe(outcome: failed) == expected):
        return panic(message: "check failed")
    let succeeded: Result[Int, Int] = ok(value: 3)
    let unchanged: Result[Int, String] = ok(value: 3)
    if not (describe(outcome: succeeded) == unchanged):
        return panic(message: "check failed")
