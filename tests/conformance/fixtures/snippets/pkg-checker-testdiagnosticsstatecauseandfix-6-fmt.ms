# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:25 TestDiagnosticsStateCauseAndFix
def g(a: Int) -> Int:
    return a

def f() -> Int:
    return g()
