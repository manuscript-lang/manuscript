# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:167 TestAnalysisProjectScopes
import value from "@lib"

export fn main() Int:
    return value()
