# conform: tags=diagnostics,sets,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:53 TestDiagnosticsStateCauseAndFix
def f() -> Int:
    let s = Set[String]()
    return 0
