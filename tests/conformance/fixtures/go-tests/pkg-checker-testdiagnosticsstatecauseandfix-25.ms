# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:44 TestDiagnosticsStateCauseAndFix
fn f() Int:
    return [1, 2].length
