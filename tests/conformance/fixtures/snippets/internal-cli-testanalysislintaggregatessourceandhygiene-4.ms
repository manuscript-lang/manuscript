# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:76 TestAnalysisLintAggregatesSourceAndHygiene
export def broken() -> Int:
    return missing
