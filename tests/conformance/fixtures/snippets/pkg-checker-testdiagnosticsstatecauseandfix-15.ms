# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:34 TestDiagnosticsStateCauseAndFix
def f(values: List[Int]) -> Unit:
    values.delete(0)
