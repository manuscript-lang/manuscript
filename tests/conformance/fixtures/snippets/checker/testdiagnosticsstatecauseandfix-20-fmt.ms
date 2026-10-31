# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:39 TestDiagnosticsStateCauseAndFix
fn f(n: Int?) Int:
    return 1 + n
