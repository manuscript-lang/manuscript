# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:61 TestDiagnosticsStateCauseAndFix
def positive(n: Int) -> Bool:
    return n > 0

def f() -> Int:
    return [1].filter(positive).length()
