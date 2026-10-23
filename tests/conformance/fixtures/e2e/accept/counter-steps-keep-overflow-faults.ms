# conform: tags=closures,control-flow,modules,mutation,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/counter-steps-keep-overflow-faults.ms
import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

fn count_up(limit: Int) Int:
    var i = limit - 3
    var steps = 0

    while i < limit:
        steps = steps + 1
        i = i + 1

    return steps

fn count_down(limit: Int) Int:
    var i = limit + 3
    var steps = 0

    while i > limit:
        steps = steps + 1
        i = i - 1

    return steps

fn reset_then_step() Int:
    var i = 0

    while i < 1:
        i = 9223372036854775807
        i = i + 1

    return i

fn nested_reset(flag: Bool) Int:
    var i = 0

    while i < 1:
        if flag:
            i = 9223372036854775807
        i = i + 1

    return i

test "counts reach the extreme without a fault":
    count_up(limit: 9223372036854775807) | try expect_equal(3)
    count_down(limit: -9223372036854775807) | try expect_equal(3)

test "reassigned counter still faults":
    let message = try expect_fault(
        fn():
            let ignored = reset_then_step()
    )
    message | try expect_contains("Int overflow;")

test "conditionally reassigned counter still faults":
    let message = try expect_fault(
        fn():
            let ignored = nested_reset(flag: true)
    )
    message | try expect_contains("Int overflow;")
