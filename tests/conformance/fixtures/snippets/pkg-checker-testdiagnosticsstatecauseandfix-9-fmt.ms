# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:28 TestDiagnosticsStateCauseAndFix
def id[T](x: T) -> T:
    return x

def f() -> Int:
    let g = id
    return g(1)
