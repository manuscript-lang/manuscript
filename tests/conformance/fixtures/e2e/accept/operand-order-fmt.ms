# conform: tags=control-flow,formatter,match,modules,mutation,optional,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/operand-order.ms
from "@std/testing.ms" import expect_equal

export def main() -> Int:
    var number = 1
    let total = number + (
        match some(1):
            case some(value):
                number += 1
                value
            case none: 0
    )
    if total != 2:
        return 1

    return 0

test "operands retain evaluation order":
    main() | try expect_equal(0)
