# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:49 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    let x: Int = 3.5
    let y = x + 1
    return y
