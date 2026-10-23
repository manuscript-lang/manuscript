# conform: tags=closures,formatter,generics,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/inline-functions.ms
import {expect_equal} from "@std/testing.ms"

type Transform:
    operation: fn(value: Int) Int

fn apply[T](operation: fn(value: T) T, value: T) T:
    return operation(value)

test "inline callbacks survive contextual rechecking":
    let value = apply(value: 3, fn(value): return value + 1)
    try expect_equal(value, 4)

    let transform = Transform(fn(value): return value + 2)
    try expect_equal(transform.operation(3), 5)
