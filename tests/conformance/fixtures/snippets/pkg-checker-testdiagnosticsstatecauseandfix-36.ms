# conform: tags=closures,diagnostics,faults,generics,lists,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:55 TestDiagnosticsStateCauseAndFix
fn pick[T](items: List[T], keep: fn(T) Bool) Optional[T]:
    return none

fn f() Int:
    let nums = [1, 2]
    let hit = pick(nums, fn(value: Int) Bool: value > 1)
    return hit.get(0)
