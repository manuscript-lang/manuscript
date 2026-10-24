# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:60 TestDiagnosticsStateCauseAndFix
def double(n: Int) -> Int:
    return n * 2

def f() -> Int:
    return [1, 2].map(double).length()
