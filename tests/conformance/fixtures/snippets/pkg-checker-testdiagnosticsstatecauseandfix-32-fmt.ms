# conform: tags=alternatives,formatter,generics,match,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:51 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing

fn f(c: Choice[Int], o: Optional[Int]) Int:
    match o:
        Optional.some(n): return n
        Optional.none: return 0

    match c:
        Choice.Found(v): return v
        Choice.Missing: return 0
