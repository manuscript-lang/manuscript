# conform: tags=closures,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-05.ms
import expect_equal from "@std/test.ms"

fn increase(value: Int) Int:
    return value + 1

fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

test "function label compatibility":
    let transform: fn(Int) Int = increase
    try expect_equal(apply(4, transform), 5)
