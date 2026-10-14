import panic from "@std/faults.ms"

import TaskGroup from "@std/tasks.ms"

type Transform:
    operation: fn(value: Int) -> Int

fn apply[T](operation: fn(value: T) -> T, value: T) -> T:
    return operation(value: value)

test "inline callbacks survive contextual rechecking":
    let value = apply(
        value: 3,
        operation: fn(value):
            return value + 1
    )
    if not (value == 4):
        return panic(message: "check failed")

    let transform = Transform(
        fn(value):
            return value + 2
    )
    if not (transform.operation(value: 3) == 5):
        return panic(message: "check failed")

    with group = TaskGroup():
        let first_task = group.start(
            fn():
                return 4
        )

        match group.join():
            ok(_): unit
            error(_):
                return panic(message: "Unexpected case")

        match first_task.join():
            ok(value):
                if value != 4:
                    return panic(message: "check failed")

            error(_):
                return panic("task result unavailable")
