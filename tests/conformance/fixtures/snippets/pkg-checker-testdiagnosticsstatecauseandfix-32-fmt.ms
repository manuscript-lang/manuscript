# conform: tags=alternatives,formatter,generics,match,optional,parser,records,tier-core
# conform: phase=parse
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
