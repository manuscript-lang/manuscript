# conform: tags=closures,control-flow,formatter,generics,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/closures.ms
from "@std/testing.ms" import expect_equal

def apply(value: Int, action: Callable[[Int], Int]) -> Int:
    return action(value)

def countdown[T](value: T, count: Int) -> T:
    if count == 0:
        return value

    return countdown(value, count - 1)

test "closures borrow the variable and shadowing":
    var offset = 1
    offset = 10

    let action = lambda (value: Int):
        return value + offset

    if True:
        var local = 20
        local = 30
        try expect_equal(action(local), 40)

    try expect_equal(action(3), 13)
    try expect_equal(offset, 10)
    try expect_equal(countdown("ready", 4), "ready")

    let factory = lambda (value: Int) -> Callable[[Int], Int]:
        return lambda inner:
            return inner + offset
    let nested = factory(value: 99)
    offset = 100
    try expect_equal(nested(1), 11)
