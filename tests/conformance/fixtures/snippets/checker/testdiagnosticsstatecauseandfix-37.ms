# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:56 TestDiagnosticsStateCauseAndFix
fn f() Int:
    return "abc".length()
