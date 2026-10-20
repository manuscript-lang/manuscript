# conform: tags=alternatives,formatter,generics,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
type Choice[T]:
    case Found(value: T)
    case Missing
fn f(c: Choice[Int]) Int:
    match c:
        Choice[String].Found(v): return 1
        Choice[String].Missing: return 0
