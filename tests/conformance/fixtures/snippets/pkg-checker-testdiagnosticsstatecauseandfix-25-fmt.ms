# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:44 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    return [1, 2].length
