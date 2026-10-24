# conform: tags=formatter,lists,maps,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:26 TestDiagnosticFixes
def f() -> Int:
    let m = Map[List[Int], Int]()
    return 0
