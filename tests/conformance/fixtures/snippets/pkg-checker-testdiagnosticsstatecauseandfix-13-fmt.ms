# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:32 TestDiagnosticsStateCauseAndFix
type P:
    x: Int

def f(p: P) -> Int:
    return p.y
