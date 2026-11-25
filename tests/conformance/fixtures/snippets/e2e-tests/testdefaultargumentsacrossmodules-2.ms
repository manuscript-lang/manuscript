// conform: tags=control-flow,diagnostics,modules,stdlib-testing,testing,tier-core
// conform: phase=check
// conform: origin=tests/e2e/e2e_test.go:510 TestDefaultArgumentsAcrossModules
import (
	expect_true, fail from "@std/test/test.ms",

	defaulted from "./library.ms",
)

fn private_value() Int {
	return 99
}

test "defaults use their declaration module" {
	copy := defaulted
	if defaulted() != 7 or copy() != 7 or defaulted(0) != 0 {
		return fail("incorrect default scope")
	}
}
// expect-error: MS2002 4:1 cannot find module ./library.ms (looked for library.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
