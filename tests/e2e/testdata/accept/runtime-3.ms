import Result from "@std/result.ms"
import map_error from "@std/result.ms"
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
    assert flag
    match number:
        ok(value):
            assert value == 3
        error(_):
            assert false
    return ok(value: unit)

test "pack helper":
    match probe():
        ok(_):
            assert true
        error(_):
            assert false

test "explicit error conversion":
    let failed: Result[Int, Int] = error(cause: 7)
    let translate = fn(cause: Int) -> String:
        return "Error {cause}"
    let converted = map_error(result: failed, transform: translate)
    let expected: Result[Int, String] = error(cause: "Error 7")
    assert converted == expected
