# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:130 TestDelimiterContinuationMayDedentBelowSuite
fn f() Int:
    let x = [
1,
2,
]
    return 0
