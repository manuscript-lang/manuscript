# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:31 TestDiagnosticsStateCauseAndFix
fn start[T](operation: fn() T) Int:
    return 0
fn work(n: Int) Int:
    return n
fn f() Int:
    return start(work)
