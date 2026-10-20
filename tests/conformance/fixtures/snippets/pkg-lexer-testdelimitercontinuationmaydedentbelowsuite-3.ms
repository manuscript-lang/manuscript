# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:132 TestDelimiterContinuationMayDedentBelowSuite
fn f() Int:
    if true:
        let x = [
1
]
        return 0
    return 1
