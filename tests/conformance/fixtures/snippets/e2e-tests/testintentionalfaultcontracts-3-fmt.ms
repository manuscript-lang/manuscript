// conform: tags=closures,faults,formatter,modules,parser,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/intentional_faults_test.go:57 TestIntentionalFaultContracts
import expect_contains, expect_fault from "@std/test/test.ms"
import panic from "@std/core.ms"

test "expect_fault reports the injected fault":
    expect_contains(expect_fault(fn: panic("boom"))?, "boom")?
