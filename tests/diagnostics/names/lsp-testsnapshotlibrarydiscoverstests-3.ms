// conform: tags=diagnostics,formatter,modules,testing,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:331 TestSnapshotLibraryDiscoversTests
import value from "../src/value.ms"

test "checks source" {
	invalid Int := "wrong"
}
// expect-error: MS2002 4:1 cannot find module ../src/value.ms (looked for <SCRATCH>/src); check the spelling, make sure the file exists, and that the path is relative to the importing file
