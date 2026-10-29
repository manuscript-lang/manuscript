# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:29 TestDiagnosticFixes
type Point:
    x: Int

fn f() Int:
    Point = 2
    return 0
