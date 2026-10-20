# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:25 TestDiagnosticsStateCauseAndFix
fn g(a: Int) Int:
    return a
fn f() Int:
    return g()
