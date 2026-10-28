# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:41 TestDiagnosticsStateCauseAndFix
fn f(n: Optional[Int]) Int:
    return n
