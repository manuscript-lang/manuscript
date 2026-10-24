# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:31 TestDiagnosticsStateCauseAndFix
def start[T](operation: Callable[[], T]) -> Int:
    return 0

def work(n: Int) -> Int:
    return n

def f() -> Int:
    return start(work)
