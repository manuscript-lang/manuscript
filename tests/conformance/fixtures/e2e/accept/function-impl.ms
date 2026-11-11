// conform: tags=closures,control-flow,generics,interfaces,interpolation,modules,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/function-impl.ms
import expect_equal from "@std/test/test.ms"

interface Apply[T]:
    fn apply(value: Int) T

type Box[T]:
    value: T

fn Box[fn(Int) T].apply(value: Int) T:
    return self.value(value)

fn render(value: Int) String:
    return "{value}"

test "implementation variables inside function signatures":
    box := Box(render)
    expect_equal(box.apply(3), "3")?

    operation: Apply[String] := box
    expect_equal(operation.apply(4), "4")?
