# conform: tags=diagnostics,numbers,sets,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:25 TestDiagnosticFixes
def f() -> Int:
    let s = Set[Float]()
    return 0
