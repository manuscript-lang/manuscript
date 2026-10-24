# conform: tags=diagnostics,modules,stdlib-faults,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:48 TestDiagnosticsStateCauseAndFix
from "@std/core.ms" import nope

def f() -> Unit:
    return
