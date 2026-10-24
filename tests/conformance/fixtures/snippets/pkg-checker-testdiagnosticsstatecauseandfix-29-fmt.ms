# conform: tags=formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:48 TestDiagnosticsStateCauseAndFix
from "@std/core.ms" import nope

def f() -> Unit:
    return
