# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:73 TestAnalysisLintAggregatesSourceAndHygiene
from "./shared.ms" import value

export def main() -> Int:
    return value()
