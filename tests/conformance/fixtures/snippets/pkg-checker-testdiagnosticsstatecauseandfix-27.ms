# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:46 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    let s = null
    return 0
