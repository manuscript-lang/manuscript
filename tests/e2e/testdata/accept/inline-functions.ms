import List from "@std/collections.ms"
import parallel_map from "@std/tasks.ms"

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
    assert value == 4
    let transform = Transform(
        operation: fn(value: Int) -> Int:
            return value + 2
    )
    assert transform.operation(value: 3) == 5
    match parallel_map(
        items: [1, 2],
        limit: 1,
        operation: fn(item: Int) -> Int:
            return item + 3
    ):
        ok(values):
            assert values == [4, 5]
        error(_):
            assert false
