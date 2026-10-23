# conform: tags=control-flow,formatter,lists,modules,mutation,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/compound-assignment.ms
import {expect_equal, expect_false} from "@std/testing.ms"

type Counter:
    count: Int
    label: String

type Outer:
    inner: Counter

fn tally(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

test "compound assignment on bindings":
    var number = 20
    number += 5
    number -= 3
    number *= 2
    number /= 4
    number %= 7

    var ratio = 1.5
    ratio *= 2.0

    var text = "a"
    text += "b"
    try expect_false(number != 4 or ratio != 3.0 or text != "ab")

test "right side groups as one operand":
    var number = 10
    number -= 4 - 1
    number *= 1 + 1
    try expect_equal(number, 14)

test "compound assignment on fields":
    var counter = Counter(1, "x")
    counter.count += 4
    counter.count *= counter.count
    counter.label += "y"

    var outer = Outer(counter.clone())
    outer.inner.count -= 5
    try expect_false(
        (
            counter.count != 25
            or counter.label != "xy"
            or outer.inner.count != 20
            or tally([1, 2, 3]) != 6
        )
    )

test "compound assignment in loops":
    var index = 0
    var total = 0

    while index < 5:
        total += index
        index += 1

    try expect_false(total != 10 or index != 5)
