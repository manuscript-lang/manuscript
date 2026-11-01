# conform: tags=closures,control-flow,formatter,generics,interfaces,interpolation,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/function-impl.ms
import expect_equal from "@std/test/test.ms"

interface Apply[T]:
    fn apply(value: Int) T

type Box[T]:
    value: T

impl Apply[T] for Box[fn(Int) T]:
    fn apply(value: Int) T:
        return self.value(value)

fn render(value: Int) String:
    return "{value}"

test "implementation variables inside function signatures":
    let box = Box(render)
    try expect_equal(box.apply(3), "3")

    let operation: Apply[String] = box
    try expect_equal(operation.apply(4), "4")
