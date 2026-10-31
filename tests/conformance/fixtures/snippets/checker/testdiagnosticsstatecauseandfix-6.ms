# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:25 TestDiagnosticsStateCauseAndFix
fn g(a: Int) Int:
    return a

fn f() Int:
    return g()
