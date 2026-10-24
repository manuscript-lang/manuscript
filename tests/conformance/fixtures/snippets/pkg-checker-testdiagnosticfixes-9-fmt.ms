# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:29 TestDiagnosticFixes
type Point:
    x: Int

def f() -> Int:
    Point = 2
    return 0
