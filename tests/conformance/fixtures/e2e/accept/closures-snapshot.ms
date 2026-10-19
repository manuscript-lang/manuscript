# conform: tags=closures,modules,mutation,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/closures-snapshot.ms
import {expect_equal, expect_true} from "@std/testing.ms"

test "snapshot captures":
    var offset = 3
    let first = fn():
        return offset
    offset = 99
    let second = fn():
        return true
    first() | try expect_equal(expected: 3)
    second() | try expect_true
