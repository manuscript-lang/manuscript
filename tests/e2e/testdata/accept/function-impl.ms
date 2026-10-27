from "@std/test.ms" import expect_equal

interface Apply[T]:
    def apply(value: Int) -> T

type Box[T]:
    value: T

impl Apply[T] for Box[Callable[[Int], T]]:
    def apply(value: Int) -> T:
        return self.value(value)

def render(value: Int) -> String:
    return f"{value}"

test "implementation variables inside function signatures":
    let box = Box(render)
    try expect_equal(box.apply(3), "3")

    let operation: Apply[String] = box
    try expect_equal(operation.apply(4), "4")
