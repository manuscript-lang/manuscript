# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/intentional_faults_test.go:12 TestIntentionalFaultContracts
from "@std/testing.ms" import expect_equal
from "@std/core.ms" import panic

def positive(value: Int) -> Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

def discard(value: Int) -> Unit:
    return

test "return contracts":
    positive(value: 3) | try expect_equal(expected: 3)
    discard(value: 1) | try expect_equal(expected: ())
