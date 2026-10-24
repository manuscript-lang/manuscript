# conform: tags=closures,diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:31 TestDiagnosticsStateCauseAndFix
def start[T](operation: Callable[[], T]) -> Int:
    return 0

def work(n: Int) -> Int:
    return n

def f() -> Int:
    return start(work)
