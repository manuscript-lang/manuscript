# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:21 TestDiagnosticsStateCauseAndFix
fn f() Unit:
    return panic(message: "x")
