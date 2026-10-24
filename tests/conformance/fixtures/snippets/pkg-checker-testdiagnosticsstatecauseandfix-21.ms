# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:40 TestDiagnosticsStateCauseAndFix
def p() -> Result[Int, Error]:
    return ok(1)

def f() -> Int:
    return p() + 1
