// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/analysis_test.go:73 TestAnalysisLintAggregatesSourceAndHygiene
import value from "./shared.ms"

export fn main() Int {
	return value()
}
// expect-error: MS2002 4:1 cannot find module ./shared.ms (looked for shared.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
