# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:58 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    let n = "abc".foo()
    return 0
