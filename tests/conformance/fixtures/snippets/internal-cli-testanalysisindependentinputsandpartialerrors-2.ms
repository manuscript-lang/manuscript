# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:33 TestAnalysisIndependentInputsAndPartialErrors
export def main() -> Int:
    return "wrong"
