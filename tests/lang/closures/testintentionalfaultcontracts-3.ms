// conform: tags=closures,faults,formatter,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/intentional_faults_test.go:57 TestIntentionalFaultContracts
import (
	panic from "@std/core.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

test "expect_fault reports the injected fault" {
	expect_contains(expect_fault(() => panic("boom"))?, "boom")?
}
