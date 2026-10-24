# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:167 TestAnalysisProjectScopes
from "@lib" import value

export def main() -> Int:
    return value()
