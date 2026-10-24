# conform: tags=alternatives,diagnostics,generics,match,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:51 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing

def f(c: Choice[Int], o: Optional[Int]) -> Int:
    match o:
        case Optional.some(n): return n
        case Optional.none: return 0

    match c:
        case Choice.Found(v): return v
        case Choice.Missing: return 0
