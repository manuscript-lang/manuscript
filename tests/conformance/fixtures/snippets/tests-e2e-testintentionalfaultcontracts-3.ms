# conform: tags=closures,faults,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/intentional_faults_test.go:57 TestIntentionalFaultContracts
from "@std/test.ms" import expect_contains, expect_fault
from "@std/core.ms" import panic

test "expect_fault reports the injected fault":
    try expect_contains(try expect_fault(lambda: panic("boom")), "boom")
