# conform: tags=formatter,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:33 TestDiagnosticsStateCauseAndFix
def f(values: Set[Int]) -> Unit:
    values.insert(1)
