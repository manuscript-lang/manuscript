# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:34 TestDiagnosticsStateCauseAndFix
fn f(values: List[Int]) Unit:
    values.delete(0)
