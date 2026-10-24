# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:167 TestAnalysisProjectScopes
from "@lib" import value

export def main() -> Int:
    return value()
