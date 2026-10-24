# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:131 TestDelimiterContinuationMayDedentBelowSuite
def f() -> Int:
    let x = (1 + 2)
    return 0
