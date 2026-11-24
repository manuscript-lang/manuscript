// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lint_program_test.go:52 TestImportUsesStayWithinTheirModule
import (
	helper from "./helper.ms",
	value from "./value.ms",
)

fn answer() Int {
	return value() + helper()
}
