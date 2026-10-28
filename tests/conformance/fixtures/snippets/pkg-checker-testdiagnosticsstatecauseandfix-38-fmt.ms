# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:57 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let n = "abc".len()
    return 0
