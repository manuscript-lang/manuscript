# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:29 TestDiagnosticsStateCauseAndFix
fn g[T](x: T) Int:
    return 0

fn f() Int:
    return g()
