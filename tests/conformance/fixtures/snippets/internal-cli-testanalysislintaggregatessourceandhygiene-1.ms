# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:73 TestAnalysisLintAggregatesSourceAndHygiene
from "./shared.ms" import value

export def main() -> Int:
    return value()
