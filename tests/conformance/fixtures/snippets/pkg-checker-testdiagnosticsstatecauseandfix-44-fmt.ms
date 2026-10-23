# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-cleanup,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:63 TestDiagnosticsStateCauseAndFix
import Closeable from "@std/core.ms"

type R:
    n: Int

impl Closeable for R:
    fn close() Unit:
        return unit

fn mk() Result[R, Error]:
    return ok(R(n: 1))

fn f() Int:
    with x = mk():
        return 1
    return 0
