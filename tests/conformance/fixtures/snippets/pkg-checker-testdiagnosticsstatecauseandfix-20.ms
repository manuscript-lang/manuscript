# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:39 TestDiagnosticsStateCauseAndFix
def f(n: Optional[Int]) -> Int:
    return 1 + n
