# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:54 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let s = SetBuilder[String]()
    return 0
