import {expect_equal, expect_false, fail} from "@std/testing.ms"
import TaskGroup from "@std/tasks.ms"

type Transform:
    operation: fn(value: Int) Int

fn apply[T](operation: fn(value: T) T, value: T) T:
    return operation(value)

test "inline callbacks survive contextual rechecking":
    let value = apply(
        value: 3,
        fn(value):
            return value + 1
    )
    try expect_equal(value, 4)
    let transform = Transform(
        fn(value):
            return value + 2
    )
    try expect_equal(transform.operation(3), 5)

    with group = TaskGroup():
        let first_task = group.start(
            fn():
                return 4
        )
        try expect_false(group.join().is_error())

        if let value = first_task.join():
            try expect_equal(value, 4)
        else:
            return fail("task result unavailable")
