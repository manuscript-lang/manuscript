# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:47 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let x = 1
    return x()
