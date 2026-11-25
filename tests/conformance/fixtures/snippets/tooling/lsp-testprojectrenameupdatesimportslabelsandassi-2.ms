// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:58 TestProjectRenameUpdatesImportsLabelsAndAssignments
import add from "./helper.ms"

fn result() Int {
	return add(value: 1)
}
// expect-error: MS2002 4:1 cannot find module ./helper.ms (looked for helper.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
