// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/hints_test.go:49 TestDiagnosticsStateCauseAndFix
fn f() Int:
    x: Int = 3.5
    y := x + 1
    return y
