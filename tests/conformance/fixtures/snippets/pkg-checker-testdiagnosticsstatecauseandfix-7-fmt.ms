# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:26 TestDiagnosticsStateCauseAndFix
fn g(amount: Int) Int:
    return amount
fn f() Int:
    return g(amunt: 1)
