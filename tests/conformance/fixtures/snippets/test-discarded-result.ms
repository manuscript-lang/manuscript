# conform: tags=diagnostics,testing,tier-stdlib,try-result
# conform: phase=check
from "@std/test.ms" import expect_equal

test "a discarded expectation checks nothing":
    let _ = expect_equal(1, 2)
