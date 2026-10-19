# conform: tags=closures,control-flow,formatter,lists,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-18.ms
import {expect_equal} from "@std/testing.ms"

fn apply(value: Int, transform: fn(value: Int) Int) Int:
    return transform(value: value)

test "function suite boundaries":
    var calls: List[Int] = []
    let dormant = fn() Unit:
        calls.append(1)
    let grouped = apply(
        transform: (
            fn(value):
                if value > 0:
                    return value - 1

                return 0
        ),
        value: 3
    )
    let final_argument = apply(
        value: 3,
        transform: fn(value):
            return value - 1
    )
    calls.length() | try expect_equal(expected: 0)
    grouped | try expect_equal(expected: 2)
    final_argument | try expect_equal(expected: 2)
