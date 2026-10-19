# conform: tags=faults,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/collection-call-order.ms
import {expect_equal} from "@std/testing.ms"

test "receiver before index":
    var values = [7]
    let index: Optional[Int] = some(0)
    let result = values.get(
        match index:
            some(i):
                values = [9]
                i
            none: 0
    )
    try expect_equal(result, 7)
