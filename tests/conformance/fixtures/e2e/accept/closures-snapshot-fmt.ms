# conform: tags=closures,formatter,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/closures-snapshot.ms
import expect_equal, expect_true from "@std/test/test.ms"

test "closures read the variable they borrow":
    var offset = 3
    offset = 99

    let first = fn:
        return offset
    let second = fn:
        return true
    first() | try expect_equal(99)
    second() | try expect_true
