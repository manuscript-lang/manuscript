# conform: tags=control-flow,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/operand-order.ms
from "@std/test.ms" import expect_equal

export def main() -> Int:
    var number = 1
    let total = (
        number
        + (
            match some(1):
                case some(value):
                    number += 1
                    value
                case none: 0
        )
    )
    if total != 2:
        return 1

    return 0

test "operands retain evaluation order":
    main() | try expect_equal(0)
