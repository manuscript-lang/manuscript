# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:24 TestDiagnosticsStateCauseAndFix
fn f() Int:
    let x = 1
    x = 2
    return x
