# conform: tags=closures,diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:31 TestDiagnosticsStateCauseAndFix
fn start[T](operation: fn() T) Int:
    return 0
fn work(n: Int) Int:
    return n
fn f() Int:
    return start(work)
