# conform: tags=faults,formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:30 TestDiagnosticFixes
import panic from "@std/faults.ms"
fn f() Int:
    panic = 2
    return 0
