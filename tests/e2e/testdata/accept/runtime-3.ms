import panic from "@std/faults.ms"
import ExecutionError from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"

fn identity[T](value: T) T:
    return value

fn probe() Result[Unit, ExecutionError]:
    let first = fn() Result[Int, String]:
        return ok(3)
    let second = fn():
        return true

    with group = TaskGroup():
        let number_task = identity(group.start(first))
        let flag_task = group.start(second)
        let number = try number_task.join()
        let flag = try flag_task.join()
        if not (flag):
            return panic(message: "check failed")

        match number:
            ok(value):
                if not (value == 3):
                    return panic(message: "check failed")
            error(_):
                return panic(message: "Unexpected case")

        return ok(unit)

test "typed task helper":
    match probe():
        ok(_):
            let completed = unit
        error(_):
            return panic(message: "Unexpected case")

fn describe(outcome: Result[Int, Int]) Result[Int, String]:
    match outcome:
        ok(value):
            return ok(value)
        error(cause):
            return error("Error {cause}")

test "explicit error conversion":
    let failed: Result[Int, Int] = error(7)
    let expected: Result[Int, String] = error("Error 7")
    if not (describe(outcome: failed) == expected):
        return panic(message: "check failed")

    let succeeded: Result[Int, Int] = ok(3)
    let unchanged: Result[Int, String] = ok(3)
    if not (describe(outcome: succeeded) == unchanged):
        return panic(message: "check failed")
