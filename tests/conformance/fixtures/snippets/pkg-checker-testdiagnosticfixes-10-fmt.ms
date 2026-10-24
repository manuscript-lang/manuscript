# conform: tags=faults,formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:30 TestDiagnosticFixes
from "@std/core.ms" import panic

def f() -> Int:
    panic = 2
    return 0
