# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:26 TestDiagnosticsStateCauseAndFix
def g(amount: Int) -> Int:
    return amount

def f() -> Int:
    return g(amunt: 1)
