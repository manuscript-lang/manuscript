# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:153 TestAnalysisStandaloneDirectoryBoundariesAndEmpty
from "../a.ms" import main

export def value() -> Int:
    return main()
