# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:41 TestDiagnosticsStateCauseAndFix
fn f(n: Optional[Int]) Int:
    return n
