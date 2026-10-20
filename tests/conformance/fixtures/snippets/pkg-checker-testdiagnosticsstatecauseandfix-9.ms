# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:28 TestDiagnosticsStateCauseAndFix
fn id[T](x: T) T:
    return x
fn f() Int:
    let g = id
    return g(1)
