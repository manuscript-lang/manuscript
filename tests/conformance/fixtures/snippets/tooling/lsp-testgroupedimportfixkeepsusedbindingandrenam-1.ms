// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/features_test.go:344 TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets
import first, second from "./helper.ms"

fn answer() Int {
	return first()
}
// expect-error: MS2002 4:1 cannot find module ./helper.ms (looked for helper.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
