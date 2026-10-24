# conform: tags=control-flow,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:38 TestDiagnosticsStateCauseAndFix
def f(n: Optional[Int]) -> Int:
    if n == 0:
        return 1

    return 0
