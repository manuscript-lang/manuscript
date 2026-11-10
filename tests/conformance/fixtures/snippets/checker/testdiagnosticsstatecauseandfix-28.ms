// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:47 TestDiagnosticsStateCauseAndFix
fn f() Int:
    x := 1
    return x()
