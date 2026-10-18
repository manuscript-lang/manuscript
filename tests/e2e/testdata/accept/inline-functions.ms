import {expect_equal, fail} from "@std/testing.ms"
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
    value | try expect_equal(expected: 4)
    let transform = Transform(
        fn(value):
            return value + 2
    )
    transform.operation(value: 3) | try expect_equal(expected: 5)

    with group = TaskGroup():
        let first_task = group.start(
            fn():
                return 4
        )

        match group.join():
            ok(_): unit
            error(_):
                return fail(message: "Unexpected case")

        match first_task.join():
            ok(value):
                try expect_equal(value, 4)
            error(_):
                return fail("task result unavailable")
