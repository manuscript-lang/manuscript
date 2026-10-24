# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:33 TestDiagnosticFixes
type Int:
    x: Int

def f() -> Int:
    let t = Int(x: 2)
    return 0
