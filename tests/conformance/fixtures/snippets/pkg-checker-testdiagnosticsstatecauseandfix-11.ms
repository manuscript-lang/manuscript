# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:30 TestDiagnosticsStateCauseAndFix
type Optional:
    x: Int

fn f(o: Optional[Int]) Int:
    return 0
