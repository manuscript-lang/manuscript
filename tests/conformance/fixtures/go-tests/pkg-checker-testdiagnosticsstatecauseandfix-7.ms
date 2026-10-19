# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:26 TestDiagnosticsStateCauseAndFix
fn g(amount: Int) Int:
    return amount
fn f() Int:
    return g(amunt: 1)
