# conform: tags=formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:48 TestDiagnosticsStateCauseAndFix
import nope from "@std/faults.ms"
fn f() Unit:
    return
