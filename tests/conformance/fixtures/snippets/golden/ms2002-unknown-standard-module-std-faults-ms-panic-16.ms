// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

test "expect_fault reports the injected fault" {
	expect_contains(expect_fault(() => panic("boom"))?, "boom")?
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 9:40 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
