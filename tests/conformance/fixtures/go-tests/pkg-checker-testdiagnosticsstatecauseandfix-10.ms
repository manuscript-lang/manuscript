# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:29 TestDiagnosticsStateCauseAndFix
fn g[T](x: T) Int:
    return 0
fn f() Int:
    return g()
