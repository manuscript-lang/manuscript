# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:56 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    return "abc".length()
