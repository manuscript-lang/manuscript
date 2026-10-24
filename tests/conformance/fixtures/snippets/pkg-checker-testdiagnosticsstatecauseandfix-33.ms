# conform: tags=alternatives,diagnostics,generics,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing

def f(c: Choice[Int]) -> Int:
    match c:
        case Choice[String].Found(v): return 1
        case Choice[String].Missing: return 0
