# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:27 TestDiagnosticsStateCauseAndFix
interface I:
    def m() -> Int

interface J:
    def m() -> Int

type A:
    n: Int

impl I for A:
    def m() -> Int: return 1

impl J for A:
    def m() -> Int: return 2

def f(a: A) -> Int:
    return a.m()
