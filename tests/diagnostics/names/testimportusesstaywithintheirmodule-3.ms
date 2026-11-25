// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:52 TestImportUsesStayWithinTheirModule
import (
	helper from "./helper.ms",
	value from "./value.ms",
)

fn answer() Int {
	return value() + helper()
}
// expect-error: MS2002 4:1 cannot find module ./helper.ms (looked for helper.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
