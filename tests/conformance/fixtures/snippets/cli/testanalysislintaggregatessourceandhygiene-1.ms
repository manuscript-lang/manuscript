# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:73 TestAnalysisLintAggregatesSourceAndHygiene
import value from "./shared.ms"

export fn main() Int:
    return value()
