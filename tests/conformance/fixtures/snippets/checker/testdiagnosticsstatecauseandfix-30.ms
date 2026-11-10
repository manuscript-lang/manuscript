// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:49 TestDiagnosticsStateCauseAndFix
fn f() Int:
    x: Int = 3.5
    y := x + 1
    return y
