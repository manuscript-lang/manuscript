# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-cleanup,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:63 TestDiagnosticsStateCauseAndFix
from "@std/core.ms" import Closeable

type R:
    n: Int

impl Closeable for R:
    def close() -> Unit:
        return ()

def mk() -> Result[R, Error]:
    return ok(R(n: 1))

def f() -> Int:
    with mk() as x:
        return 1
    return 0
