// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/analysis_test.go:17 TestOverlayImportsAndNavigation
import answer from "./dep.ms"

fn value() Int {
	return answer()
}
// expect-error: MS2002 4:1 cannot find module ./dep.ms (looked for dep.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
