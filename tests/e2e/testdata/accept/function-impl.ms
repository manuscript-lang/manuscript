import {expect_equal} from "@std/testing.ms"

interface Apply[T]:
    fn apply(value: Int) -> T

type Box[T]:
    value: T

impl Apply[T] for Box[fn(value: Int) -> T]:
    fn apply(value: Int) -> T:
        return self.value(value: value)

fn render(value: Int) -> String:
    return "{value}"

test "implementation variables inside function signatures":
    let box = Box(render)
    box.apply(value: 3) | try expect_equal(expected: "3")
    let operation = Apply[String](box)
    operation.apply(value: 4) | try expect_equal(expected: "4")
