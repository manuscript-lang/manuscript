# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:28 TestDiagnosticFixes
fn helper() Int:
    return 1
fn f() Int:
    helper = 2
    return 0
