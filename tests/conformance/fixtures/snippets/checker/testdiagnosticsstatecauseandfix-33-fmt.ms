// conform: tags=alternatives,formatter,generics,match,parser,records,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
enum Choice[T]:
    Found(value: T)
    Missing

fn f(c: Choice[Int]) Int:
    match c:
        Choice[String].Found(v): return 1
        Choice[String].Missing: return 0
