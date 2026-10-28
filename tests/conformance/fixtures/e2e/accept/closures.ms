# conform: tags=closures,control-flow,generics,modules,mutation,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/closures.ms
import expect_equal from "@std/test.ms"

fn apply(value: Int, action: fn(Int) Int) Int:
    return action(value)

fn countdown[T](value: T, count: Int) T:
    if count == 0:
        return value

    return countdown(value, count - 1)

test "closures borrow the variable and shadowing":
    var offset = 1
    offset = 10

    let action = fn(value: Int):
        return value + offset

    if true:
        var local = 20
        local = 30
        try expect_equal(action(local), 40)

    try expect_equal(action(3), 13)
    try expect_equal(offset, 10)
    try expect_equal(countdown("ready", 4), "ready")

    let factory = fn(value: Int) fn(Int) Int:
        return fn inner:
            return inner + offset
    let nested = factory(value: 99)
    offset = 100
    try expect_equal(nested(1), 11)
