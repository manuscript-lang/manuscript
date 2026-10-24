# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:153 TestAnalysisStandaloneDirectoryBoundariesAndEmpty
from "../a.ms" import main

export def value() -> Int:
    return main()
