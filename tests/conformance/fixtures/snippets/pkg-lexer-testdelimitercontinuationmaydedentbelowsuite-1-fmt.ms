# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:130 TestDelimiterContinuationMayDedentBelowSuite
def f() -> Int:
    let _x = [1, 2]
    return 0
