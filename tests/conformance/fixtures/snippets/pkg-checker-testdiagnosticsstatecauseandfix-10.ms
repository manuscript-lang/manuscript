# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:29 TestDiagnosticsStateCauseAndFix
def g[T](x: T) -> Int:
    return 0

def f() -> Int:
    return g()
