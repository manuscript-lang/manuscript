# conform: tags=diagnostics,numbers,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:42 TestDiagnosticsStateCauseAndFix
def f() -> Float:
    let x: Float = 3
    return x
