# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:60 TestDiagnosticsStateCauseAndFix
def double(n: Int) -> Int:
    return n * 2

def f() -> Int:
    return [1, 2].map(double).length()
