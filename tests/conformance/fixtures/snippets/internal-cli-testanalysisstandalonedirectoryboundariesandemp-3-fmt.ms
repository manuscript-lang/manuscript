# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:153 TestAnalysisStandaloneDirectoryBoundariesAndEmpty
import main from "../a.ms"
export fn value() Int:
    return main()
