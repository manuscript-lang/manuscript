// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lint_program_test.go:51 TestImportUsesStayWithinTheirModule
import value from "./value.ms"

export fn helper() Int {
	return 2
}
// expect-error: MS2002 4:1 cannot find module ./value.ms (looked for value.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
