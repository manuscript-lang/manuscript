# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:25 TestDiagnosticsStateCauseAndFix
def g(a: Int) -> Int:
    return a

def f() -> Int:
    return g()
