# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:59 TestDiagnosticsStateCauseAndFix
fn f() String:
    return [1.5].join(separator: ",")
