import panic from "@std/faults.ms"

import parallel from "@std/tasks.ms"

type Transform:
    operation: fn(value: Int) -> Int

fn apply[T](operation: fn(value: T) -> T, value: T) -> T:
    return operation(value: value)

test "inline callbacks survive contextual rechecking":
    let value = apply(
        value: 3,
        operation: fn(value: Int) -> Int:
            return value + 1
    )
    if not (value == 4):
        return panic(message: "check failed")
    let transform = Transform(
        operation: fn(value: Int) -> Int:
            return value + 2
    )
    if not (transform.operation(value: 3) == 5):
        return panic(message: "check failed")
    match parallel(tasks: [fn() -> Int:
        return 4
    ]):
        ok(values):
            let [value] = values
            if value != 4:
                return panic(message: "check failed")
        error(_):
            return panic(message: "Unexpected case")
