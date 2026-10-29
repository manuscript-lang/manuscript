# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:58 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let n = "abc".foo()
    return 0
