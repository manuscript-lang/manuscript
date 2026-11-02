# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:33 TestDiagnosticsStateCauseAndFix
fn f(values: Set[Int]) Unit:
    values.insert(1)
