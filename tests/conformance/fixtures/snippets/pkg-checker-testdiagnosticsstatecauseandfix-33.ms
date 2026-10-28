# conform: tags=alternatives,diagnostics,generics,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing

fn f(c: Choice[Int]) Int:
    match c:
        Choice[String].Found(v): return 1
        Choice[String].Missing: return 0
