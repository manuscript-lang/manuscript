# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:33 TestDiagnosticFixes
type Int:
    x: Int

def f() -> Int:
    let t = Int(x: 2)
    return 0
