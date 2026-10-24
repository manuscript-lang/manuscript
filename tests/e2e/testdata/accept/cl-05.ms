from "@std/testing.ms" import expect_equal

def increase(value: Int) -> Int:
    return value + 1

def apply(value: Int, transform: Callable[[Int], Int]) -> Int:
    return transform(value)

test "function label compatibility":
    let transform: Callable[[Int], Int] = increase
    try expect_equal(apply(4, transform), 5)
