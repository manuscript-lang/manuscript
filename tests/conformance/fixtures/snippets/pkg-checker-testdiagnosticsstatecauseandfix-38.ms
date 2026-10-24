# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:57 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    let n = "abc".len()
    return 0
