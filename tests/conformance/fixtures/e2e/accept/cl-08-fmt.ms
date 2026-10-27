# conform: tags=control-flow,formatter,lists,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-08.ms
from "@std/test.ms" import expect_equal

def selected_sum(values: List[Int]) -> Int:
    var total = 0

    for value in values:
        if value == 0:
            continue
        if value < 0:
            break

        total += value

    return total

test "iteration control":
    try expect_equal(selected_sum([2, 0, 3, -1, 9]), 5)
    try expect_equal(selected_sum([]), 0)
