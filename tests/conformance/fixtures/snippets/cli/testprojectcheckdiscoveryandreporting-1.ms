// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/project_check_test.go:49 TestProjectCheckDiscoveryAndReporting
import value from "./lib/value.ms"

export fn main() Int {
	return value()
}
// expect-error: MS2002 4:1 cannot find module ./lib/value.ms (looked for lib); check the spelling, make sure the file exists, and that the path is relative to the importing file
