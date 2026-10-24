# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:36 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    return "a" + 1
