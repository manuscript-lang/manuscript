# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:28 TestDiagnosticFixes
def helper() -> Int:
    return 1

def f() -> Int:
    helper = 2
    return 0
