# conform: tags=closures,formatter,generics,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/inline-functions.ms
from "@std/test.ms" import expect_equal

type Transform:
    operation: Callable[[Int], Int]

def apply[T](operation: Callable[[T], T], value: T) -> T:
    return operation(value)

test "inline callbacks survive contextual rechecking":
    let applied = apply(value: 3, lambda value: return value + 1)
    try expect_equal(applied, 4)

    let transform = Transform(lambda value: return value + 2)
    try expect_equal(transform.operation(3), 5)
