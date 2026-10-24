# conform: tags=alternatives,formatter,generics,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing

def f(c: Choice[Int]) -> Int:
    match c:
        case Choice[String].Found(v): return 1
        case Choice[String].Missing: return 0
