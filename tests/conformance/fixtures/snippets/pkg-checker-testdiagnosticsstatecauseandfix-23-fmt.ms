# conform: tags=formatter,numbers,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:42 TestDiagnosticsStateCauseAndFix
def f() -> Float:
    let x: Float = 3
    return x
