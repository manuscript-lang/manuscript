# conform: tags=closures,control-flow,formatter,generics,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/closures.ms
import {expect_equal} from "@std/testing.ms"

fn apply(value: Int, action: fn(value: Int) Int) Int:
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
        var offset = 20
        offset = 30
        try expect_equal(action(offset), 40)

    try expect_equal(action(3), 13)

    try expect_equal(offset, 10)
    try expect_equal(countdown("ready", 4), "ready")
    let factory = fn(value: Int) fn(value: Int) Int:
        return fn(value):
            return value + offset
    let nested = factory(value: 99)
    offset = 100
    try expect_equal(nested(1), 11)
