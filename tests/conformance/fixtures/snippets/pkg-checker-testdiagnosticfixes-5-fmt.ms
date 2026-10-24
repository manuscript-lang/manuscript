# conform: tags=formatter,numbers,parser,sets,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:25 TestDiagnosticFixes
def f() -> Int:
    let s = Set[Float]()
    return 0
