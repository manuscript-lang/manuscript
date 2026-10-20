# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:153 TestAnalysisStandaloneDirectoryBoundariesAndEmpty
import main from "../a.ms"
export fn value() Int:
    return main()
