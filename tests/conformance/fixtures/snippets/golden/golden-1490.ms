// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

test "expect_fault reports the injected fault" {
	expect_contains(expect_fault(() => panic("boom"))?, "boom")?
}
