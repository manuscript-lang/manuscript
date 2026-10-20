# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:46 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let s = null
    return 0
