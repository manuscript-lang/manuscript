# conform: tags=diagnostics,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/interface_views/conformance_test.ms
from "./domain.ms" import invoke
from "./left.ms" import left
from "./right.ms" import right
from "@std/test.ms" import expect_equal

test "each module keeps its own view implementation":
    let first = left()
    let second = right()
    let bound = first.read
    bound() | try expect_equal(11)
    second.read() | try expect_equal(22)
    invoke(first) | try expect_equal(11)
    invoke(second) | try expect_equal(22)
