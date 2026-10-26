# conform: tags=closures,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/cl-05.ms
from "@std/test.ms" import expect_equal

def increase(value: Int) -> Int:
    return value + 1

def apply(value: Int, transform: Callable[[Int], Int]) -> Int:
    return transform(value)

test "function label compatibility":
    let transform: Callable[[Int], Int] = increase
    try expect_equal(apply(4, transform), 5)
