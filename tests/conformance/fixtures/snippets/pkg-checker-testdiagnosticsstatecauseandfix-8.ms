# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:27 TestDiagnosticsStateCauseAndFix
interface I:
    fn m() Int

interface J:
    fn m() Int

type A:
    n: Int

impl I for A:
    fn m() Int: return 1

impl J for A:
    fn m() Int: return 2

fn f(a: A) Int:
    return a.m()
