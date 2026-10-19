# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:73 TestAnalysisLintAggregatesSourceAndHygiene
import value from "./shared.ms"
export fn main() Int:
    return value()
