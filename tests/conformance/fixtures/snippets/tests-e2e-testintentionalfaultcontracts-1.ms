# conform: tags=control-flow,faults,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/intentional_faults_test.go:12 TestIntentionalFaultContracts
import {expect_equal} from "@std/testing.ms"
import panic from "@std/faults.ms"

fn positive(value: Int) Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) Unit:
    return

test "return contracts":
    positive(value: 3) | try expect_equal(expected: 3)
    discard(value: 1) | try expect_equal(expected: unit)
