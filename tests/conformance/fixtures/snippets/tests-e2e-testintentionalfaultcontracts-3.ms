# conform: tags=closures,faults,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/intentional_faults_test.go:57 TestIntentionalFaultContracts
import {expect_contains, expect_fault} from "@std/test.ms"
import panic from "@std/core.ms"

test "expect_fault reports the injected fault":
    try expect_contains(try expect_fault(fn: panic("boom")), "boom")
