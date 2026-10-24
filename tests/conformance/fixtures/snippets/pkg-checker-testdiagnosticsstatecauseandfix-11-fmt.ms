# conform: tags=formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:30 TestDiagnosticsStateCauseAndFix
type Optional:
    x: Int

def f(o: Optional[Int]) -> Int:
    return 0
