# conform: tags=control-flow,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:38 TestDiagnosticsStateCauseAndFix
fn f(n: Optional[Int]) Int:
    if n == 0:
        return 1

    return 0
