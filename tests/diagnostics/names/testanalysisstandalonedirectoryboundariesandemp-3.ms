// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/analysis_test.go:153 TestAnalysisStandaloneDirectoryBoundariesAndEmpty
import main from "../a.ms"

export fn value() Int {
	return main()
}
// expect-error: MS2002 4:1 cannot find module ../a.ms (looked for <SCRATCH>/a.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
