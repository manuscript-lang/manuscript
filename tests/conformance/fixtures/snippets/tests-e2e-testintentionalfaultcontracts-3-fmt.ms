# conform: tags=closures,faults,formatter,modules,parser,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/intentional_faults_test.go:57 TestIntentionalFaultContracts
from "@std/testing.ms" import expect_contains, expect_fault
from "@std/core.ms" import panic

test "expect_fault reports the injected fault":
    try expect_contains(try expect_fault(lambda: panic("boom")), "boom")
