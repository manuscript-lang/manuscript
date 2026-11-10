// conform: tags=closures,faults,formatter,generics,lists,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/hints_test.go:55 TestDiagnosticsStateCauseAndFix
fn pick[T](items: List[T], keep: fn(T) Bool) T?:
    return none

fn f() Int:
    nums := [1, 2]
    hit := pick(nums, fn(value: Int) Bool: value > 1)
    return hit.get(0)
