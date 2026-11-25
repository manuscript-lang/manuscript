// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/cli_test.go:232 TestProjectLintChecksImportedSource
import value from "./other.ms"

fn read() Int {
	return value()
}
// expect-error: MS2002 4:1 cannot find module ./other.ms (looked for other.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
