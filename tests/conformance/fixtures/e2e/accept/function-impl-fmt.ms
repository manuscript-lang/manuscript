# conform: tags=closures,control-flow,formatter,generics,interfaces,interpolation,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/function-impl.ms
from "@std/testing.ms" import expect_equal

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
