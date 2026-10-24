# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:132 TestDelimiterContinuationMayDedentBelowSuite
def f() -> Int:
    if True:
        let x = [1]
        return 0

    return 1
