// conform: tags=control-flow,diagnostics,faults,formatter,modules,stdlib-testing,testing,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/e2e_test.go:547 TestFieldDefaultsAcrossModules
import (
	expect_true, fail from "@std/test/test.ms",

	Box from "./data.ms",
)

test "imported constructor retains default module and generic scope" {
	box := Box(value: "text")
	if box.copied != "text" or box.items.get(0) != "text" {
		return fail("imported generic defaults")
	}
}
// expect-error: MS2002 4:1 cannot find module ./data.ms (looked for data.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
