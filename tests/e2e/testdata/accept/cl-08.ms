import {expect_equal} from "@std/testing.ms"

fn selected_sum(values: List[Int]) -> Int:
    var total = 0

    for value in values:
        if value == 0:
            continue
        if value < 0:
            break

        total = total + value

    return total

test "iteration control":
    selected_sum(values: [2, 0, 3, -1, 9]) | try expect_equal(expected: 5)
    selected_sum(values: []) | try expect_equal(expected: 0)
