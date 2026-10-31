# conform: tags=diagnostics,testing,tier-stdlib,try-result
# conform: phase=check
import expect_equal from "@std/test.ms"

test "a discarded expectation checks nothing":
    let _ = expect_equal(1, 2)
