# conform: tags=closures,generics,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/inline-functions.ms
import expect_equal from "@std/test.ms"

type Transform:
    operation: fn(Int) Int

fn apply[T](operation: fn(T) T, value: T) T:
    return operation(value)

test "inline callbacks survive contextual rechecking":
    let applied = apply(value: 3, fn value: return value + 1)
    try expect_equal(applied, 4)

    let transform = Transform(fn value: return value + 2)
    try expect_equal(transform.operation(3), 5)
