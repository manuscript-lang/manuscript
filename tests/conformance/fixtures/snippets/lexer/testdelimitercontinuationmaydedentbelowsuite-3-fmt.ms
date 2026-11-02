# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:132 TestDelimiterContinuationMayDedentBelowSuite
fn f() Int:
    if true:
        let _x = [1]
        return 0

    return 1
